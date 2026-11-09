import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/pc_camera.dart';
import 'call_camera.dart';

/// The PC's camera during a video call, through the same library that
/// reads codes with it (`pc_camera.dart`). Its pictures are made small and
/// squeezed into JPEG here, a few times a second, away from the thread that
/// draws the screen. Nothing is written to disk.
///
/// Not yet verified on devices.
class PcCallCamera extends CallCamera {
  PcCallCamera._(this._camera);

  /// The camera, or null where there is no radio library to reach it.
  static PcCallCamera? open() {
    final camera = PcCamera.open();
    return camera == null ? null : PcCallCamera._(camera);
  }

  final PcCamera _camera;
  Timer? _looking;
  int _last = 0;
  bool _squeezing = false;
  void Function(Uint8List jpeg, int quarterTurns)? _picture;

  /// How wide a picture is sent, in pixels.
  static const width = 320;

  /// About eight pictures a second.
  static const _every = Duration(milliseconds: 125);

  @override
  Future<bool> start(
    void Function(Uint8List jpeg, int quarterTurns) picture,
  ) async {
    await stop();
    _picture = picture;
    _camera.start();
    // Windows takes a moment to open a camera.
    for (var tries = 0; tries < 40; tries++) {
      switch (_camera.state) {
        case 'on':
          _looking = Timer.periodic(_every, (_) => _look());
          return true;
        case 'denied' || 'none' || 'failed':
          _camera.stop();
          _picture = null;
          return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _camera.stop();
    _picture = null;
    return false;
  }

  Future<void> _look() async {
    if (_squeezing) return;
    final frame = _camera.frame(after: _last);
    if (frame == null) return;
    _last = frame.seq;
    _squeezing = true;
    try {
      final small = shrink(frame, width);
      final jpeg = await Isolate.run(() => squeeze(small));
      if (jpeg != null) _picture?.call(jpeg, 0);
    } finally {
      _squeezing = false;
    }
  }

  @override
  Future<void> stop() async {
    _looking?.cancel();
    _looking = null;
    _picture = null;
    _camera.stop();
  }
}

/// A picture made at most [width] pixels wide, keeping its shape, as RGB.
/// Each pixel is the nearest one of the original: quick, and plenty for a
/// picture this small.
({int width, int height, Uint8List rgb}) shrink(CameraFrame frame, int width) {
  final scale = frame.width <= width ? 1.0 : frame.width / width;
  final w = (frame.width / scale).floor();
  final h = (frame.height / scale).floor();
  final rgb = Uint8List(w * h * 3);
  var at = 0;
  for (var y = 0; y < h; y++) {
    final row = (y * scale).floor() * frame.width;
    for (var x = 0; x < w; x++) {
      final from = (row + (x * scale).floor()) * 4;
      // BGRA in, RGB out.
      rgb[at++] = frame.pixels[from + 2];
      rgb[at++] = frame.pixels[from + 1];
      rgb[at++] = frame.pixels[from];
    }
  }
  return (width: w, height: h, rgb: rgb);
}

/// JPEG small enough for one frame, trying lower quality until it fits.
/// Null if even the lowest does not.
Uint8List? squeeze(({int width, int height, Uint8List rgb}) small) {
  final image = img.Image.fromBytes(
    width: small.width,
    height: small.height,
    bytes: small.rgb.buffer,
    numChannels: 3,
  );
  for (final quality in [60, 45, 30]) {
    final jpeg = img.encodeJpg(
      image,
      quality: quality,
      chroma: img.JpegChroma.yuv420,
    );
    // One byte goes before it, for which way up it is.
    if (jpeg.length < CallCamera.maxBytes) return jpeg;
  }
  return null;
}
