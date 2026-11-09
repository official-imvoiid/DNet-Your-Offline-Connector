import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../calls/pc_call_camera.dart' show shrink;
import '../core/pc_camera.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';

// Must match the channel name in PhotoCamera.kt.
const _phone = MethodChannel('dnet/photo');

/// Takes a photo with the phone's own camera app (`PhotoCamera.kt`), which
/// writes it straight into the app's cache. Says why when it cannot. Gives
/// back where the photo is, or null.
///
/// Not yet verified on devices.
Future<String?> takePhotoOnPhone(BuildContext context) async {
  final l10n = context.l10n;
  Object? answer;
  try {
    answer = await _phone.invokeMethod<Object>('take');
  } on PlatformException {
    answer = null;
  } on MissingPluginException {
    answer = null;
  }
  final (state, path) = switch (answer) {
    {'state': final String state, 'path': final String path} => (state, path),
    {'state': final String state} => (state, null),
    _ => ('failed', null),
  };
  if (state == 'taken' && path != null) return path;
  if (!context.mounted) return null;
  switch (state) {
    case 'denied':
      await showAppNotice(
        context,
        title: l10n.cameraDeniedTitle,
        body: l10n.cameraDeniedBody(context.deviceKind),
      );
    case 'none':
      showAppToast(context, l10n.noCameraApp(context.deviceKind));
    case 'cancelled' || 'busy':
      break;
    default:
      showAppToast(context, l10n.photoNotTaken);
  }
  return null;
}

/// Saves [frame] as a JPEG in [folder], and clears out photos left there
/// from more than a week ago, which have long been sent. Gives back the
/// new photo's path, or null if it could not be written.
String? savePhoto(CameraFrame frame, String folder) {
  try {
    final dir = Directory(folder)..createSync(recursive: true);
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    for (final old in dir.listSync().whereType<File>()) {
      if (old.lastModifiedSync().isBefore(weekAgo)) old.deleteSync();
    }
    // Plenty for a photo in a chat, and no bigger than it needs to be.
    final rgb = shrink(frame, frame.width < 1920 ? frame.width : 1920);
    final jpeg = img.encodeJpg(
      img.Image.fromBytes(
        width: rgb.width,
        height: rgb.height,
        bytes: rgb.rgb.buffer,
        numChannels: 3,
      ),
      quality: 90,
    );
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'photo-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.jpg';
    final file = File('$folder${Platform.pathSeparator}$name')
      ..writeAsBytesSync(jpeg, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}

/// The PC's camera, for a photo to send. Shows what the camera sees, as in
/// a mirror. The photo itself is kept the right way round, as a phone
/// keeps a selfie, and is shown that way once taken, to take again or use.
/// Gives back where the photo was saved, or null.
///
/// Only the photo the user chooses to use is written down, in the app's
/// own folder. The camera goes off when this screen closes.
///
/// Not yet verified on devices.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.camera, required this.folder});

  final PcCamera camera;

  /// Where the photo is saved: a folder of the app's own.
  final String folder;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  Timer? _tick;
  int _seq = 0;
  String _state = 'starting';

  /// What the camera sees now, and the picture it was made from.
  ui.Image? _live;
  CameraFrame? _liveFrame;

  /// The photo taken, until it is used or taken again.
  ui.Image? _taken;
  CameraFrame? _takenFrame;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.camera.start();
    // About as often as the camera keeps a picture.
    _tick = Timer.periodic(const Duration(milliseconds: 66), (_) => _look());
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.camera.stop();
    _live?.dispose();
    _taken?.dispose();
    super.dispose();
  }

  void _look() {
    // Held still while the user looks at the photo they took.
    if (_takenFrame != null) return;
    final state = widget.camera.state;
    if (state != _state) setState(() => _state = state);
    if (state != 'on') {
      // It will not come on by itself after failing.
      if (state != 'starting') _tick?.cancel();
      return;
    }
    final frame = widget.camera.frame(after: _seq);
    if (frame == null) return;
    _seq = frame.seq;
    ui.decodeImageFromPixels(
      frame.pixels,
      frame.width,
      frame.height,
      ui.PixelFormat.bgra8888,
      (image) {
        if (!mounted || _takenFrame != null) {
          image.dispose();
          return;
        }
        setState(() {
          _live?.dispose();
          _live = image;
          _liveFrame = frame;
        });
      },
    );
  }

  void _take() {
    final (live, frame) = (_live, _liveFrame);
    if (live == null || frame == null) return;
    setState(() {
      _taken = live.clone();
      _takenFrame = frame;
    });
  }

  void _retake() {
    setState(() {
      _taken?.dispose();
      _taken = null;
      _takenFrame = null;
    });
  }

  Future<void> _use() async {
    final frame = _takenFrame;
    if (frame == null || _saving) return;
    final l10n = context.l10n;
    setState(() => _saving = true);
    final folder = widget.folder;
    // Off the screen's thread: a big picture takes a moment to squeeze.
    final path = await Isolate.run(() => savePhoto(frame, folder));
    if (!mounted) return;
    if (path == null) {
      setState(() => _saving = false);
      showAppToast(context, l10n.photoNotTaken);
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (live, taken) = (_live, _taken);
    final Widget view;
    if (taken != null) {
      view = Center(
        child: AspectRatio(
          aspectRatio: taken.width / taken.height,
          child: RawImage(image: taken, fit: BoxFit.contain),
        ),
      );
    } else if (_state == 'on' && live != null) {
      view = Center(
        child: AspectRatio(
          aspectRatio: live.width / live.height,
          // As in a mirror, which is how people expect to see themselves.
          child: Transform.flip(
            flipX: true,
            child: RawImage(image: live, fit: BoxFit.contain),
          ),
        ),
      );
    } else if (_state == 'starting' || _state == 'on') {
      view = Center(
        child: Text(
          l10n.cameraStarting,
          style: AppText.base.copyWith(color: AppColors.text2),
        ),
      );
    } else {
      view = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.cameraUnavailableTitle,
                textAlign: TextAlign.center,
                style: AppText.rowTitle,
              ),
              if (_state != 'none') ...[
                const SizedBox(height: 8),
                Text(
                  l10n.cameraUnavailableBody,
                  textAlign: TextAlign.center,
                  style: AppText.base.copyWith(color: AppColors.text2),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return AppScreen(
      header: AppTopBar(title: l10n.cameraTitle),
      body: ColoredBox(color: AppColors.bg, child: view),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: taken != null
            ? Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: l10n.retakePhoto,
                      onTap: _saving ? null : _retake,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: l10n.usePhoto,
                      kind: AppButtonKind.primary,
                      onTap: _saving ? null : _use,
                    ),
                  ),
                ],
              )
            : Center(
                child: _Shutter(
                  label: l10n.takePhoto,
                  onTap: _state == 'on' && live != null ? _take : null,
                ),
              ),
      ),
    );
  }
}

/// The round button that takes the photo.
class _Shutter extends StatelessWidget {
  const _Shutter({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ready = onTap != null;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      focusRadius: BorderRadius.circular(36),
      child: Opacity(
        opacity: ready ? 1 : 0.4,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.text, width: 4),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.text,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
