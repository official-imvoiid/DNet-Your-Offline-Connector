import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/action_list.dart';
import '../widgets/buttons.dart';
import 'call_icons.dart';
import 'screen_share.dart';

/// Someone's shared screen, fitted into the space given, with their name
/// and a button to see it bigger.
class SharedScreenView extends StatelessWidget {
  const SharedScreenView({
    super.key,
    required this.screen,
    required this.name,
    this.onEnlarge,
  });

  final SharedScreen screen;

  /// Who is sharing it.
  final String name;
  final VoidCallback? onEnlarge;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = l10n.screenShareTheirs(name);
    return Semantics(
      container: true,
      label: label,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ScreenPicture(screen: screen),
              Positioned(
                left: 10,
                top: 10,
                child: _Label(icon: CallIcons.screen, text: label),
              ),
              if (onEnlarge != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: AppIconButton(
                    icon: CallIcons.enlarge,
                    label: l10n.screenShareEnlarge,
                    background: const Color(0x99000000),
                    round: true,
                    onTap: onEnlarge,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shared screen filling the whole window, to read it closely. Pinch or
/// scroll to zoom further.
class ScreenViewer extends StatelessWidget {
  const ScreenViewer({
    super.key,
    required this.screen,
    required this.name,
    required this.onClose,
  });

  final SharedScreen screen;
  final String name;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const AppIcon(
                    CallIcons.screen,
                    size: 18,
                    color: AppColors.text2,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.screenShareTheirs(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.barTitle,
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: CallIcons.shrink,
                    label: l10n.screenShareShrink,
                    onTap: onClose,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                maxScale: 6,
                child: ScreenPicture(screen: screen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pieces of a shared screen drawn where they go, keeping its shape.
/// Each piece is turned from JPEG into a picture here, once, and kept only
/// as long as it is on the screen: none goes into the app's image cache.
class ScreenPicture extends StatefulWidget {
  const ScreenPicture({super.key, required this.screen});

  final SharedScreen screen;

  @override
  State<ScreenPicture> createState() => _ScreenPictureState();
}

class _ScreenPictureState extends State<ScreenPicture> {
  /// Each piece's picture, by where it goes, with the JPEG it came from.
  final Map<(int, int, int, int), (Uint8List, ui.Image?)> _drawn = {};
  int _gen = -1;

  @override
  void initState() {
    super.initState();
    widget.screen.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(ScreenPicture old) {
    super.didUpdateWidget(old);
    if (!identical(old.screen, widget.screen)) {
      old.screen.removeListener(_changed);
      widget.screen.addListener(_changed);
      _clear();
      _changed();
    }
  }

  @override
  void dispose() {
    widget.screen.removeListener(_changed);
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final (_, image) in _drawn.values) {
      image?.dispose();
    }
    _drawn.clear();
  }

  void _changed() {
    final screen = widget.screen;
    if (screen.gen != _gen) {
      _gen = screen.gen;
      _clear();
    }
    final now = {for (final piece in screen.pieces) piece.rect: piece};
    for (final key in _drawn.keys.toList()) {
      if (!now.containsKey(key)) _drawn.remove(key)?.$2?.dispose();
    }
    for (final MapEntry(key: rect, value: piece) in now.entries) {
      final had = _drawn[rect];
      if (had != null && identical(had.$1, piece.jpeg)) continue;
      // The old picture stays until the new one is ready, so nothing
      // flickers.
      _drawn[rect] = (piece.jpeg, had?.$2);
      _decode(rect, piece.jpeg);
    }
    if (mounted) setState(() {});
  }

  Future<void> _decode((int, int, int, int) rect, Uint8List jpeg) async {
    ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      image = (await codec.getNextFrame()).image;
      codec.dispose();
    } on Object {
      return;
    }
    final now = _drawn[rect];
    if (!mounted || now == null || !identical(now.$1, jpeg)) {
      image.dispose();
      return;
    }
    now.$2?.dispose();
    _drawn[rect] = (jpeg, image);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screen = widget.screen;
    final ready = _drawn.values.any((d) => d.$2 != null);
    if (!ready || screen.width == 0) {
      return Center(
        child: Text(
          context.l10n.screenShareWaiting,
          style: AppText.detail,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: screen.width / screen.height,
        child: CustomPaint(
          painter: _ScreenPainter(
            width: screen.width,
            height: screen.height,
            pieces: [
              for (final piece in screen.pieces)
                if (_drawn[piece.rect]?.$2 case final image?)
                  (piece.rect, image),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenPainter extends CustomPainter {
  _ScreenPainter({
    required this.width,
    required this.height,
    required this.pieces,
  });

  final int width;
  final int height;
  final List<((int, int, int, int), ui.Image)> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / width;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final ((x, y, w, h), image) in pieces) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        // A hair wider, so no seam shows between pieces when scaled.
        Rect.fromLTWH(x * scale, y * scale, w * scale + 0.5, h * scale + 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScreenPainter old) => true;
}

/// What the user can share: each screen, then each window, for a sheet.
class ScreenPicker extends StatelessWidget {
  const ScreenPicker({super.key, required this.sources, required this.onPick});

  final List<ScreenSource> sources;
  final ValueChanged<ScreenSource> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screens = sources.where((s) => !s.window).toList();
    final windows = sources.where((s) => s.window).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.screenSharePickTitle, style: AppText.barTitle),
            ),
            const SizedBox(height: 6),
            Text(l10n.screenSharePickNote, style: AppText.detail),
            const SizedBox(height: 14),
            if (screens.isNotEmpty)
              ActionGroup(
                actions: [
                  for (final (index, source) in screens.indexed)
                    SheetAction(
                      icon: CallIcons.screen,
                      label: screens.length == 1
                          ? l10n.screenShareWhole
                          : l10n.screenShareNumber(index + 1),
                      value: screens.length > 1 && source.primary
                          ? l10n.screenShareMain
                          : null,
                      onTap: () => onPick(source),
                    ),
                ],
              ),
            if (windows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l10n.screenShareWindows, style: AppText.sectionLabel),
              const SizedBox(height: 8),
              ActionGroup(
                actions: [
                  for (final source in windows)
                    SheetAction(
                      icon: CallIcons.screen,
                      label: source.name,
                      onTap: () => onPick(source),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Says plainly that the user's screen is being shared, with a button to
/// stop.
class SharingBar extends StatelessWidget {
  const SharingBar({super.key, required this.sharing, required this.onStop});

  /// What is shared.
  final ScreenSource sharing;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = sharing.window && sharing.name.isNotEmpty
        ? l10n.screenShareYouAreWindow(sharing.name)
        : l10n.screenShareYouAre;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const AppIcon(CallIcons.screen, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.base.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: l10n.screenShareStopShort,
              kind: AppButtonKind.danger,
              height: 44,
              horizontalPadding: 14,
              onTap: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.icon, required this.text});

  final AppIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 14, color: AppColors.text),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.base.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
