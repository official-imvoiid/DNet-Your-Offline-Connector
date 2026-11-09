import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/sticker_maker.dart';
import '../data/stickers.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/action_list.dart';
import '../widgets/app_switch.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/scaffold.dart';
import '../widgets/text_box.dart';
import 'sticker_packs_screen.dart';

/// The shape a sticker made from a photo is cut to.
enum StickerShape { free, rounded, circle }

/// Asks for a photo, from the device or the camera, and opens the sticker
/// maker with it.
Future<void> startStickerMaker(BuildContext context) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  var from = 'pick';
  if (state.canTakePhoto) {
    final chosen = await showAppSheet<String>(
      context,
      builder: (context) => ActionGroup(
        actions: [
          SheetAction(
            icon: AppIcons.photo,
            label: l10n.stickerFromPhoto,
            onTap: () => Navigator.of(context).pop('pick'),
          ),
          SheetAction(
            icon: AppIcons.camera,
            label: l10n.stickerFromCamera,
            onTap: () => Navigator.of(context).pop('camera'),
          ),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;
    from = chosen;
  }
  final path = from == 'camera'
      ? await state.takePhoto(context)
      : await state.pickFile();
  if (path == null || !context.mounted) return;
  await makeStickerFrom(context, path);
}

/// Makes a sticker from the picture at [path]: a GIF as it is, so it keeps
/// moving, and anything else in the sticker maker.
Future<void> makeStickerFrom(BuildContext context, String path) async {
  if (path.toLowerCase().endsWith('.gif')) {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final pack = state.stickerPacks.isEmpty
        ? null
        : await chooseStickerPack(context, title: l10n.saveToPack);
    if (!context.mounted) return;
    if (pack == null && state.stickerPacks.isNotEmpty) return;
    final kept = await state.keepStickerFrom(path, packId: pack);
    if (!context.mounted) return;
    showAppToast(context, kept ? l10n.stickerMade : l10n.stickerNotMade);
    return;
  }
  await Go.stickerEditor(context, path);
}

/// Makes a sticker from a photo: cut to a part of it and a shape, its
/// background taken out if the user wants, words on it if they want, and
/// saved to one of their packs. All of it is done on the device.
class StickerEditorScreen extends StatefulWidget {
  const StickerEditorScreen({super.key, required this.path});

  final String path;

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  Uint8List? _png;
  ui.Image? _photo;
  bool _unreadable = false;

  CropBox _crop = (left: 0.1, top: 0.1, width: 0.8, height: 0.8);
  StickerShape _shape = StickerShape.free;

  bool _cutOut = false;
  bool _cutting = false;
  ui.Image? _cut;
  CropBox? _cutFor;

  final _words = TextEditingController();
  String? _pack;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _words.dispose();
    _photo?.dispose();
    _cut?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final png = await loadStickerPhoto(widget.path);
    final photo = png == null ? null : await _decode(png);
    if (!mounted) return;
    if (photo == null) {
      setState(() => _unreadable = true);
      return;
    }
    setState(() {
      _png = png;
      _photo = photo;
      _crop = _square(photo, 0.8);
      final packs = AppScope.read(context).stickerPacks;
      _pack = packs.isEmpty ? null : packs.first.id;
    });
  }

  static Future<ui.Image?> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    } on Exception {
      return null;
    }
  }

  /// The biggest square, in the middle, [share] of the shorter side.
  static CropBox _square(ui.Image photo, double share) {
    final side = math.min(photo.width, photo.height) * share;
    final w = side / photo.width;
    final h = side / photo.height;
    return (left: (1 - w) / 2, top: (1 - h) / 2, width: w, height: h);
  }

  void _setShape(StickerShape shape) {
    final photo = _photo;
    setState(() {
      _shape = shape;
      if (shape == StickerShape.circle && photo != null) {
        _crop = _squared(_crop, photo);
      }
    });
    _cutAgain();
  }

  /// [crop] made square, about its middle, as big as fits.
  static CropBox _squared(CropBox crop, ui.Image photo) {
    final pw = crop.width * photo.width;
    final ph = crop.height * photo.height;
    final side = math.min(pw, ph);
    final w = side / photo.width;
    final h = side / photo.height;
    final cx = crop.left + crop.width / 2;
    final cy = crop.top + crop.height / 2;
    return (
      left: (cx - w / 2).clamp(0.0, 1 - w),
      top: (cy - h / 2).clamp(0.0, 1 - h),
      width: w,
      height: h,
    );
  }

  Future<void> _cutAgain() async {
    final png = _png;
    if (!_cutOut || png == null || _cutFor == _crop || _cutting) return;
    final crop = _crop;
    setState(() => _cutting = true);
    final cut = await cutOutBackground(png, crop);
    final image = cut == null ? null : await _decode(cut);
    if (!mounted) return;
    setState(() {
      _cutting = false;
      _cut?.dispose();
      _cut = image;
      _cutFor = image == null ? null : crop;
      if (image == null) _cutOut = false;
    });
    if (image == null) {
      showAppToast(context, context.l10n.stickerCutOutFailed);
    } else if (_crop != crop) {
      // Moved while it was being worked out.
      await _cutAgain();
    }
  }

  StickerLook get _look => StickerLook(
    photo: _photo!,
    crop: _crop,
    cut: _cutOut && _cutFor == _crop ? _cut : null,
    shape: _shape,
    words: _words.text.trim(),
  );

  Future<void> _save() async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    setState(() => _saving = true);
    final made = await renderSticker(_look);
    if (!mounted) return;
    setState(() => _saving = false);
    if (made == null || !state.keepStickerImage(made, packId: _pack)) {
      showAppToast(context, l10n.stickerNotMade);
      return;
    }
    showAppToast(context, l10n.stickerMade);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final photo = _photo;
    return AppScreen(
      header: AppTopBar(title: l10n.stickerEditorTitle),
      body: _unreadable
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.stickerPhotoUnreadable,
                  textAlign: TextAlign.center,
                  style: AppText.detail14,
                ),
              ),
            )
          : photo == null
          ? const SizedBox.shrink()
          : _editor(context, photo),
      footer: photo == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: AppButton(
                label: l10n.saveSticker,
                kind: AppButtonKind.primary,
                onTap: _saving || _cutting ? null : _save,
              ),
            ),
    );
  }

  Widget _editor(BuildContext context, ui.Image photo) {
    final l10n = context.l10n;
    final packs = AppScope.of(context).stickerPacks;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Semantics(
        header: true,
        child: Text(text, style: AppText.sectionLabel),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: AspectRatio(
            aspectRatio: photo.width / photo.height,
            child: _CropFrame(
              photo: photo,
              crop: _crop,
              shape: _shape,
              onChanged: (crop) => setState(() => _crop = crop),
              onDone: _cutAgain,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(l10n.stickerCropHint, style: AppText.detail),
        ),
        label(l10n.stickerShape),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (shape, name) in [
              (StickerShape.free, l10n.stickerShapeFree),
              (StickerShape.rounded, l10n.stickerShapeRounded),
              (StickerShape.circle, l10n.stickerShapeCircle),
            ])
              AppButton(
                label: name,
                height: 40,
                horizontalPadding: 14,
                kind: _shape == shape
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                onTap: () => _setShape(shape),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.stickerCutOut, style: AppText.rowTitle),
                    const SizedBox(height: 2),
                    Text(l10n.stickerCutOutDetail, style: AppText.detail),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppSwitch(
                value: _cutOut,
                label: l10n.stickerCutOut,
                onChanged: _cutting
                    ? null
                    : (on) {
                        setState(() => _cutOut = on);
                        _cutAgain();
                      },
              ),
            ],
          ),
        ),
        label(l10n.stickerWords),
        AppTextBox(
          controller: _words,
          label: l10n.stickerWords,
          hint: l10n.stickerWordsHint,
          onChanged: (text) {
            if (text.characters.length > _mostWords) {
              _words.text = text.characters.take(_mostWords).toString();
            }
            setState(() {});
          },
        ),
        label(l10n.stickerSaveTo),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final pack in packs)
              AppButton(
                label: pack.name.isEmpty ? l10n.myStickersTitle : pack.name,
                height: 40,
                horizontalPadding: 14,
                kind: _pack == pack.id
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                onTap: () => setState(() => _pack = pack.id),
              ),
            AppButton(
              label: l10n.newStickerPack,
              icon: AppIcons.plus,
              height: 40,
              horizontalPadding: 14,
              onTap: () async {
                final made = await newStickerPack(context);
                if (made != null && mounted) setState(() => _pack = made);
              },
            ),
          ],
        ),
        label(l10n.stickerPreview),
        Center(
          child: Semantics(
            image: true,
            label: l10n.stickerPreview,
            child: SizedBox.square(
              dimension: 140,
              child: FittedBox(
                child: SizedBox(
                  width: _look.size(140).width,
                  height: _look.size(140).height,
                  child: CustomPaint(painter: _LookPainter(_look)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const _mostWords = 40;
}

/// Everything a sticker made from a photo is drawn from.
@immutable
class StickerLook {
  const StickerLook({
    required this.photo,
    required this.crop,
    required this.shape,
    this.cut,
    this.words = '',
  });

  final ui.Image photo;
  final CropBox crop;

  /// The part inside [crop] with its background taken out, if it was.
  final ui.Image? cut;
  final StickerShape shape;
  final String words;

  /// Its size when its longer side is [longest].
  Size size(double longest) {
    final w = crop.width * photo.width;
    final h = crop.height * photo.height;
    return w >= h
        ? Size(longest, math.max(1, longest * h / w))
        : Size(math.max(1, longest * w / h), longest);
  }

  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    canvas.save();
    switch (shape) {
      case StickerShape.free:
        canvas.clipRect(whole);
      case StickerShape.rounded:
        canvas.clipRRect(
          RRect.fromRectAndRadius(
            whole,
            Radius.circular(size.shortestSide * 0.18),
          ),
        );
      case StickerShape.circle:
        canvas.clipPath(Path()..addOval(whole));
    }
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final cut = this.cut;
    if (cut != null) {
      canvas.drawImageRect(
        cut,
        Rect.fromLTWH(0, 0, cut.width.toDouble(), cut.height.toDouble()),
        whole,
        paint,
      );
    } else {
      canvas.drawImageRect(
        photo,
        Rect.fromLTWH(
          crop.left * photo.width,
          crop.top * photo.height,
          crop.width * photo.width,
          crop.height * photo.height,
        ),
        whole,
        paint,
      );
    }
    canvas.restore();
    if (words.isEmpty) return;
    var fontSize = size.shortestSide * 0.17;
    TextPainter painter(Paint foreground) => TextPainter(
      text: TextSpan(
        text: words,
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontFamilyFallback: const [AppFonts.emoji],
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          height: 1.1,
          foreground: foreground,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.92);
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    var text = painter(fill);
    while (fontSize > 8 && (text.height > size.height * 0.4)) {
      fontSize *= 0.9;
      text = painter(fill);
    }
    final edge = painter(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fontSize * 0.18
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.bg,
    );
    final at = Offset(
      (size.width - text.width) / 2,
      size.height - text.height - size.height * 0.05,
    );
    edge.paint(canvas, at);
    text.paint(canvas, at);
  }
}

class _LookPainter extends CustomPainter {
  _LookPainter(this.look);

  final StickerLook look;

  @override
  void paint(Canvas canvas, Size size) => look.paint(canvas, size);

  @override
  bool shouldRepaint(_LookPainter old) =>
      old.look.photo != look.photo ||
      old.look.crop != look.crop ||
      old.look.cut != look.cut ||
      old.look.shape != look.shape ||
      old.look.words != look.words;
}

/// Draws [look] and makes it small enough to be a sticker. Null if it
/// cannot be.
Future<Uint8List?> renderSticker(StickerLook look) async {
  final size = look.size(512);
  final recorder = ui.PictureRecorder();
  look.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) return null;
  final png = data.buffer.asUint8List();
  return Isolate.run(() => prepareStickerBytes(png));
}

/// The photo with a frame over it to choose the part that becomes the
/// sticker. The frame is moved by dragging inside it and sized by
/// dragging a corner. A circle keeps it square.
class _CropFrame extends StatefulWidget {
  const _CropFrame({
    required this.photo,
    required this.crop,
    required this.shape,
    required this.onChanged,
    required this.onDone,
  });

  final ui.Image photo;
  final CropBox crop;
  final StickerShape shape;
  final ValueChanged<CropBox> onChanged;
  final VoidCallback onDone;

  @override
  State<_CropFrame> createState() => _CropFrameState();
}

enum _Grip { move, topLeft, topRight, bottomLeft, bottomRight }

class _CropFrameState extends State<_CropFrame> {
  _Grip? _grip;

  /// The smallest the frame may be, as a share of the photo's shorter side.
  static const _least = 0.12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final c = widget.crop;
        final frame = Rect.fromLTWH(
          c.left * size.width,
          c.top * size.height,
          c.width * size.width,
          c.height * size.height,
        );
        return Semantics(
          label: context.l10n.stickerCropFrame,
          hint: context.l10n.stickerCropHint,
          image: true,
          child: GestureDetector(
            onPanStart: (d) => _grip = _gripAt(d.localPosition, frame),
            onPanUpdate: (d) => _drag(d.delta, size),
            onPanEnd: (_) {
              _grip = null;
              widget.onDone();
            },
            child: CustomPaint(
              size: size,
              painter: _FramePainter(
                photo: widget.photo,
                frame: frame,
                shape: widget.shape,
              ),
            ),
          ),
        );
      },
    );
  }

  _Grip _gripAt(Offset at, Rect frame) {
    const reach = 32.0;
    for (final (corner, grip) in [
      (frame.topLeft, _Grip.topLeft),
      (frame.topRight, _Grip.topRight),
      (frame.bottomLeft, _Grip.bottomLeft),
      (frame.bottomRight, _Grip.bottomRight),
    ]) {
      if ((corner - at).distance <= reach) return grip;
    }
    return _Grip.move;
  }

  void _drag(Offset delta, Size size) {
    final grip = _grip;
    if (grip == null || size.isEmpty) return;
    final c = widget.crop;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    final photo = widget.photo;
    final shorter = math.min(photo.width, photo.height);
    final leastW = _least * shorter / photo.width;
    final leastH = _least * shorter / photo.height;
    var left = c.left, top = c.top;
    var right = c.left + c.width, bottom = c.top + c.height;
    switch (grip) {
      case _Grip.move:
        final l = (left + dx).clamp(0.0, 1 - c.width);
        final t = (top + dy).clamp(0.0, 1 - c.height);
        widget.onChanged((left: l, top: t, width: c.width, height: c.height));
        return;
      case _Grip.topLeft:
        left = (left + dx).clamp(0.0, right - leastW);
        top = (top + dy).clamp(0.0, bottom - leastH);
      case _Grip.topRight:
        right = (right + dx).clamp(left + leastW, 1.0);
        top = (top + dy).clamp(0.0, bottom - leastH);
      case _Grip.bottomLeft:
        left = (left + dx).clamp(0.0, right - leastW);
        bottom = (bottom + dy).clamp(top + leastH, 1.0);
      case _Grip.bottomRight:
        right = (right + dx).clamp(left + leastW, 1.0);
        bottom = (bottom + dy).clamp(top + leastH, 1.0);
    }
    var next = (
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
    if (widget.shape == StickerShape.circle) {
      // Square, kept against the corner opposite the one dragged.
      final side = math.min(
        next.width * photo.width,
        next.height * photo.height,
      );
      final w = side / photo.width;
      final h = side / photo.height;
      next = (
        left: grip == _Grip.topLeft || grip == _Grip.bottomLeft
            ? right - w
            : left,
        top: grip == _Grip.topLeft || grip == _Grip.topRight ? bottom - h : top,
        width: w,
        height: h,
      );
    }
    widget.onChanged(next);
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.photo,
    required this.frame,
    required this.shape,
  });

  final ui.Image photo;
  final Rect frame;
  final StickerShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;
    canvas.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      whole,
      Paint()..filterQuality = FilterQuality.medium,
    );
    final cut = switch (shape) {
      StickerShape.free => Path()..addRect(frame),
      StickerShape.rounded =>
        Path()..addRRect(
          RRect.fromRectAndRadius(
            frame,
            Radius.circular(frame.shortestSide * 0.18),
          ),
        ),
      StickerShape.circle => Path()..addOval(frame),
    };
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(whole), cut),
      Paint()..color = const Color(0x99000000),
    );
    final line = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(frame, line);
    if (shape != StickerShape.free) canvas.drawPath(cut, line);
    final grip = Paint()..color = AppColors.accent;
    for (final corner in [
      frame.topLeft,
      frame.topRight,
      frame.bottomLeft,
      frame.bottomRight,
    ]) {
      canvas.drawCircle(corner, 7, grip);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.photo != photo || old.frame != frame || old.shape != shape;
}
