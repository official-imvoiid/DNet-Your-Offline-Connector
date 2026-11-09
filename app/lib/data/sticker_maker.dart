import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The longest side a photo is worked on at while a sticker is made from
/// it. Bigger only makes the work slower; a sticker ends up far smaller.
const stickerPhotoSize = 1024;

/// The photo at [path], turned the right way up and no bigger than
/// [stickerPhotoSize] either way, as PNG. Null if it is not a picture.
Future<Uint8List?> loadStickerPhoto(String path) => Isolate.run(() {
  try {
    return prepareStickerPhoto(File(path).readAsBytesSync());
  } on FileSystemException {
    return null;
  }
});

/// The same, from the photo's bytes.
Uint8List? prepareStickerPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    return null;
  }
  var picture = img.bakeOrientation(img.Image.from(decoded, noAnimation: true));
  if (picture.width > stickerPhotoSize || picture.height > stickerPhotoSize) {
    picture = picture.width >= picture.height
        ? img.copyResize(picture, width: stickerPhotoSize)
        : img.copyResize(picture, height: stickerPhotoSize);
  }
  return img.encodePng(picture.convert(numChannels: 4), level: 1);
}

/// A part of a picture, as fractions of its width and height.
typedef CropBox = ({double left, double top, double width, double height});

/// The part of [photo] (PNG) inside [crop], with its background made
/// see-through, as PNG. The background is what is the colour of the edges
/// of the part and joined to them. Null if no background can be told apart
/// from the rest, or the photo cannot be read.
Future<Uint8List?> cutOutBackground(Uint8List photo, CropBox crop) =>
    Isolate.run(() => cutOutBackgroundNow(photo, crop));

/// The same, here and now.
Uint8List? cutOutBackgroundNow(Uint8List photo, CropBox crop) {
  final decoded = img.decodePng(photo) ?? img.decodeImage(photo);
  if (decoded == null) return null;
  final x = (crop.left * decoded.width).round().clamp(0, decoded.width - 1);
  final y = (crop.top * decoded.height).round().clamp(0, decoded.height - 1);
  final w = (crop.width * decoded.width).round().clamp(1, decoded.width - x);
  final h = (crop.height * decoded.height).round().clamp(1, decoded.height - y);
  final part = img
      .copyCrop(decoded, x: x, y: y, width: w, height: h)
      .convert(numChannels: 4);
  final mask = backgroundMask(part);
  if (mask == null) return null;
  for (final pixel in part) {
    final keep = mask[pixel.y * part.width + pixel.x];
    pixel.a = pixel.a * keep / 255;
  }
  return img.encodePng(part, level: 1);
}

/// How much of each pixel of [picture] to keep, 0 to 255, row by row:
/// none of the background, all of the rest, and a soft edge between. Null
/// if almost all of it, or almost none, looks like background.
Uint8List? backgroundMask(img.Image picture) {
  // Worked out small, which is quick and smooths the edge, then scaled up.
  const work = 200;
  final scale = math.min(1.0, work / math.max(picture.width, picture.height));
  final small = scale < 1
      ? img.copyResize(
          picture,
          width: math.max(1, (picture.width * scale).round()),
          height: math.max(1, (picture.height * scale).round()),
          interpolation: img.Interpolation.average,
        )
      : picture;
  final w = small.width;
  final h = small.height;
  if (w < 3 || h < 3) return null;
  final r = Int32List(w * h);
  final g = Int32List(w * h);
  final b = Int32List(w * h);
  final seeThrough = Uint8List(w * h);
  for (final pixel in small) {
    final i = pixel.y * w + pixel.x;
    r[i] = pixel.r.toInt();
    g[i] = pixel.g.toInt();
    b[i] = pixel.b.toInt();
    seeThrough[i] = pixel.a < pixel.maxChannelValue / 2 ? 1 : 0;
  }
  int distance(int i, int j) {
    final dr = r[i] - r[j];
    final dg = g[i] - g[j];
    final db = b[i] - b[j];
    return dr * dr + dg * dg + db * db;
  }

  final edge = <int>[
    for (var x = 0; x < w; x++) ...[x, (h - 1) * w + x],
    for (var y = 1; y < h - 1; y++) ...[y * w, y * w + w - 1],
  ];
  // The colour most of the edge is, to start from: the edge pixel nearest
  // to the middle of the edge's colours, channel by channel.
  int middle(Int32List channel) {
    final values = [for (final i in edge) channel[i]]..sort();
    return values[values.length ~/ 2];
  }

  final mr = middle(r), mg = middle(g), mb = middle(b);
  int fromMiddle(int i) {
    final dr = r[i] - mr, dg = g[i] - mg, db = b[i] - mb;
    return dr * dr + dg * dg + db * db;
  }

  // Next to each other: this close. From where the background was first
  // met at the edge: no further than this.
  const step = 26 * 26;
  const reach = 80 * 80;
  final background = Uint8List(w * h);
  final seed = Int32List(w * h);
  final queue = <int>[];
  for (final i in edge) {
    if (background[i] == 0 && (seeThrough[i] == 1 || fromMiddle(i) <= reach)) {
      background[i] = 1;
      seed[i] = i;
      queue.add(i);
    }
  }
  for (var at = 0; at < queue.length; at++) {
    final i = queue[at];
    final x = i % w;
    final y = i ~/ w;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
      final j = ny * w + nx;
      if (background[j] == 1) continue;
      final joins =
          seeThrough[j] == 1 ||
          (distance(i, j) <= step && distance(seed[i], j) <= reach);
      if (!joins) continue;
      background[j] = 1;
      seed[j] = seed[i];
      queue.add(j);
    }
  }
  final share = queue.length / (w * h);
  if (share < 0.04 || share > 0.96) return null;
  // Kept is 255; a soft edge, blurred twice over a pixel either way.
  var keep = Float64List(w * h);
  for (var i = 0; i < w * h; i++) {
    keep[i] = background[i] == 1 ? 0 : 255;
  }
  for (var pass = 0; pass < 2; pass++) {
    final next = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0.0;
        var n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            sum += keep[ny * w + nx];
            n++;
          }
        }
        next[y * w + x] = sum / n;
      }
    }
    keep = next;
  }
  // Scaled up to the picture, smoothly.
  final out = Uint8List(picture.width * picture.height);
  for (var y = 0; y < picture.height; y++) {
    final fy = ((y + 0.5) * h / picture.height - 0.5).clamp(0.0, h - 1.0);
    final y0 = fy.floor(), y1 = math.min(y0 + 1, h - 1);
    final ty = fy - y0;
    for (var x = 0; x < picture.width; x++) {
      final fx = ((x + 0.5) * w / picture.width - 0.5).clamp(0.0, w - 1.0);
      final x0 = fx.floor(), x1 = math.min(x0 + 1, w - 1);
      final tx = fx - x0;
      final top = keep[y0 * w + x0] * (1 - tx) + keep[y0 * w + x1] * tx;
      final bottom = keep[y1 * w + x0] * (1 - tx) + keep[y1 * w + x1] * tx;
      out[y * picture.width + x] = (top * (1 - ty) + bottom * ty).round();
    }
  }
  return out;
}
