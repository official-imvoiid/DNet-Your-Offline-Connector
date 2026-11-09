import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_bounds.dart';

/// The most a profile photo may be, in bytes. It travels to contacts and,
/// inside one signed item, to members of the user's spaces, which has
/// room for no more.
const maxPhotoBytes = 32 * 1024;

/// The most a space's icon may be, in bytes. Members and people nearby who
/// find the space ask for it, so it is kept smaller than a photo.
const maxSpaceIconBytes = 24 * 1024;

/// Makes a profile photo from the picture or GIF at [path]: square, small
/// and under [maxBytes], made on this device. A GIF keeps moving, with
/// fewer frames if it has to. Null if it is not a picture that can be read
/// or cannot be made small enough.
Future<Uint8List?> preparePhoto(String path, {int maxBytes = maxPhotoBytes}) =>
    Isolate.run(
      () => preparePhotoBytes(File(path).readAsBytesSync(), maxBytes: maxBytes),
    );

/// The same, from the picture's bytes.
Uint8List? preparePhotoBytes(Uint8List bytes, {int maxBytes = maxPhotoBytes}) {
  // A file the user picked can still claim an absurd size. Not decoded.
  if (!soundImage(bytes)) return null;
  final isGif =
      bytes.length > 6 && String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF';
  if (isGif) {
    final moving = img.decodeGif(bytes);
    if (moving == null) return null;
    for (final size in const [128, 96, 64]) {
      final square = img.copyResizeCropSquare(moving, size: size);
      for (var step = 1; step <= 8; step *= 2) {
        final out = img.encodeGif(_everyNth(square, step));
        if (out.length <= maxBytes) return out;
      }
    }
    return null;
  }
  final picture = img.decodeImage(bytes);
  if (picture == null) return null;
  for (final size in const [256, 192, 128]) {
    final square = img.copyResizeCropSquare(
      img.Image.from(picture, noAnimation: true),
      size: size,
      interpolation: img.Interpolation.average,
    );
    for (final quality in const [85, 75, 65, 55]) {
      final out = img.encodeJpg(square, quality: quality);
      if (out.length <= maxBytes) return out;
    }
  }
  return null;
}

/// Every [step]th frame of an animation, each shown [step] times as long,
/// so it moves at the same speed with less to send.
img.Image _everyNth(img.Image moving, int step) {
  if (step == 1 || moving.numFrames <= 1) return moving;
  final frames = moving.frames;
  img.Image frame(int i) =>
      img.Image.from(frames[i], noAnimation: true)
        ..frameDuration = frames[i].frameDuration * step;
  final first = frame(0);
  for (var i = step; i < frames.length; i += step) {
    first.addFrame(frame(i));
  }
  return first;
}
