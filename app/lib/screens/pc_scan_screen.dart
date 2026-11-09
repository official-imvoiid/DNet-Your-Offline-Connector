import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/pc_camera.dart';
import '../data/qr_read.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/scaffold.dart';

/// The PC's camera, looking for a DNet code. Shows what the camera sees,
/// as in a mirror, and looks for a code in it a few times a second.
/// Closes with the first thing it reads, as the phone's scanner does;
/// what that means is not decided here.
///
/// Nothing is photographed or kept: pictures stay in memory and the
/// camera goes off when this screen closes.
///
/// Not yet verified on devices.
class PcScanScreen extends StatefulWidget {
  const PcScanScreen({super.key, required this.camera});

  final PcCamera camera;

  @override
  State<PcScanScreen> createState() => _PcScanScreenState();
}

class _PcScanScreenState extends State<PcScanScreen> {
  Timer? _tick;
  ui.Image? _picture;
  int _seq = 0;
  bool _reading = false;
  bool _done = false;
  String _state = 'starting';

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
    _picture?.dispose();
    super.dispose();
  }

  void _look() {
    if (_done) return;
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
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _picture?.dispose();
          _picture = image;
        });
      },
    );
    // One look at a time, off the screen's thread.
    if (_reading) return;
    _reading = true;
    final (pixels, width, height) = (frame.pixels, frame.width, frame.height);
    Isolate.run(() => readQrCode(pixels, width, height)).then(
      (read) {
        _reading = false;
        if (read == null || _done || !mounted) return;
        _done = true;
        Navigator.of(context).pop(read);
      },
      onError: (Object _) {
        _reading = false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final picture = _picture;
    final Widget view;
    if (_state == 'on' && picture != null) {
      view = Center(
        child: AspectRatio(
          aspectRatio: picture.width / picture.height,
          // As in a mirror, which is how people expect to see themselves
          // and what they hold up.
          child: Transform.flip(
            flipX: true,
            child: RawImage(image: picture, fit: BoxFit.contain),
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
                _state == 'none'
                    ? l10n.scanUnavailable('pc')
                    : l10n.cameraUnavailableTitle,
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
      header: AppTopBar(title: l10n.scanACode),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(color: AppColors.bg, child: view),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              l10n.scanHint,
              textAlign: TextAlign.center,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}
