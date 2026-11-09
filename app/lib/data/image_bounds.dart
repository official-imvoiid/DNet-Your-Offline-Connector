import 'dart:io';
import 'dart:typed_data';

/// Reads the size a picture claims to be from its header, without decoding
/// it, so a picture from someone else cannot make the app set aside a
/// huge bitmap. A 40 KB PNG can declare itself 30,000 by 30,000 pixels,
/// which is 3.6 GB once decoded: more than enough to kill the app.
///
/// Every picture that arrives over the radio (a contact's photo, a space's
/// icon, a sticker, a picture in a chat) is checked here before any
/// decoder sees it. Nothing here is cryptography: it reads a few header
/// bytes and compares numbers.
class ImageSize {
  const ImageSize(this.width, this.height);
  final int width;
  final int height;

  int get pixels => width * height;

  @override
  bool operator ==(Object other) =>
      other is ImageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width x $height';
}

/// The widest or tallest a picture may be, in pixels, and the most pixels
/// it may have. 8192 is more than any phone screen or chat bubble needs;
/// 20 million pixels is 80 MB decoded, which a phone can take once.
const maxImageSide = 8192;
const maxImagePixels = 20 * 1000 * 1000;

/// How much of a picture file is read to find its size. JPEG sizes sit
/// after the metadata; 256 KB covers any honest camera's.
const _headerRead = 256 * 1024;

/// The size [bytes] say they are, or null if they are not a PNG, JPEG,
/// GIF, WebP or BMP, or the size cannot be found in them.
ImageSize? imageSize(Uint8List bytes) {
  if (bytes.length < 10) return null;
  final data = ByteData.sublistView(bytes);
  // PNG: eight-byte signature, then the IHDR chunk with width and height.
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    if (bytes.length < 24) return null;
    if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
    return ImageSize(data.getUint32(16), data.getUint32(20));
  }
  // GIF: "GIF87a" or "GIF89a", then the logical screen size, little-endian.
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return ImageSize(
      data.getUint16(6, Endian.little),
      data.getUint16(8, Endian.little),
    );
  }
  // BMP: "BM", then the DIB header. Height may be negative (top-down).
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    if (bytes.length < 26) return null;
    return ImageSize(
      data.getInt32(18, Endian.little).abs(),
      data.getInt32(22, Endian.little).abs(),
    );
  }
  // WebP: RIFF container, then one of three kinds of first chunk.
  if (bytes.length >= 30 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    switch (String.fromCharCodes(bytes.sublist(12, 16))) {
      case 'VP8 ':
        return ImageSize(
          data.getUint16(26, Endian.little) & 0x3FFF,
          data.getUint16(28, Endian.little) & 0x3FFF,
        );
      case 'VP8L':
        final b0 = bytes[21], b1 = bytes[22], b2 = bytes[23], b3 = bytes[24];
        return ImageSize(
          1 + (((b1 & 0x3F) << 8) | b0),
          1 + (((b3 & 0xF) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6)),
        );
      case 'VP8X':
        return ImageSize(
          1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)),
          1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)),
        );
    }
    return null;
  }
  // JPEG: segments from the start, until a frame header (SOFn) says the
  // size. Anything malformed on the way means no size.
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var at = 2;
    while (at + 4 <= bytes.length) {
      if (bytes[at] != 0xFF) return null;
      final marker = bytes[at + 1];
      if (marker == 0xFF) {
        at++;
        continue;
      }
      // Standalone markers carry no length.
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        at += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) return null;
      final length = data.getUint16(at + 2);
      if (length < 2) return null;
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) {
        if (at + 9 > bytes.length) return null;
        return ImageSize(data.getUint16(at + 7), data.getUint16(at + 5));
      }
      at += 2 + length;
    }
    return null;
  }
  return null;
}

/// Whether [bytes] are a picture small enough to decode: a known kind,
/// with a size that fits [maxImageSide] and [maxImagePixels].
bool soundImage(Uint8List bytes) => switch (imageSize(bytes)) {
  final size? =>
    size.width > 0 &&
        size.height > 0 &&
        size.width <= maxImageSide &&
        size.height <= maxImageSide &&
        size.pixels <= maxImagePixels,
  null => false,
};

/// The verdicts on picture files already looked at, so a chat that is
/// scrolled does not read each file again. Bounded; the oldest go first.
final Map<String, bool> _fileVerdicts = {};
const _mostVerdicts = 256;

/// Whether the file at [path] is a picture the app may decode and show.
/// False for a file that cannot be read, is not a picture, or claims a
/// size that is too big. Only the header is read.
bool soundImageFile(String path) {
  if (path.isEmpty) return false;
  final known = _fileVerdicts[path];
  if (known != null) return known;
  bool verdict;
  try {
    final file = File(path).openSync();
    try {
      verdict = soundImage(file.readSync(_headerRead));
    } finally {
      file.closeSync();
    }
  } on FileSystemException {
    verdict = false;
  }
  if (_fileVerdicts.length >= _mostVerdicts) {
    _fileVerdicts.remove(_fileVerdicts.keys.first);
  }
  _fileVerdicts[path] = verdict;
  return verdict;
}

/// Forgets what was known about [path]. For a file written anew.
void forgetImageFile(String path) => _fileVerdicts.remove(path);
