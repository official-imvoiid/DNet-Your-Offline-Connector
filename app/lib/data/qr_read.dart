import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

/// Looks for a QR code in a picture and gives back what it says, or null
/// if there is none it can read. Runs on the device and sends nothing
/// anywhere.
///
/// [bgra] is the picture's pixels, four bytes each, in the order blue,
/// green, red, alpha, row after row: what the PC's camera gives.
String? readQrCode(Uint8List bgra, int width, int height) {
  final count = width * height;
  if (width <= 0 || height <= 0 || bgra.length < count * 4) return null;
  // Each pixel read as one number, red in the third byte from the right,
  // which is how the reader wants it. On a little-endian device the
  // bytes as they are already say that.
  final pixels = bgra.offsetInBytes % 4 == 0
      ? bgra.buffer.asInt32List(bgra.offsetInBytes, count)
      : Uint8List.fromList(bgra.sublist(0, count * 4)).buffer.asInt32List();
  final source = RGBLuminanceSource(width, height, pixels);
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  // A code is usually dark on light. Some phones in dark mode show it
  // light on dark.
  for (final seen in <LuminanceSource>[
    source,
    InvertedLuminanceSource(source),
  ]) {
    for (final binarizer in <Binarizer>[
      HybridBinarizer(seen),
      GlobalHistogramBinarizer(seen),
    ]) {
      try {
        return QRCodeReader()
            .decode(BinaryBitmap(binarizer), hints: hints)
            .text;
      } on ReaderException {
        // Not found this way. The next way may.
      } on ArgumentError {
        // A picture the reader could not make sense of.
      }
    }
  }
  return null;
}
