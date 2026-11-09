import 'dart:convert';
import 'dart:typed_data';

/// What a code for the camera starts with.
const _codePrefix = 'dnet:q/';

final _link = RegExp(r'dnet:(id|space)/[0-9a-fA-F]+');

/// The text to put in a code for the camera, for a person's link.
///
/// It says exactly what the link says, written more tightly: a camera
/// reads a small code more surely than a big one. Null if [link] is not a
/// person's link.
/// What the user's QR code holds: their key and nothing more, so the
/// square stays simple enough for any camera. Whoever scans it is beside
/// them, so everything else comes over the radio.
const _keyPrefix = 'DNET:';

/// The short code for a key, given as hex.
String shortCode(String keyHex) {
  final bytes = Uint8List(keyHex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(keyHex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return '$_keyPrefix${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The key a short code holds, as hex, or null if [read] is not one.
String? keyFromShortCode(String read) {
  final text = read.trim();
  if (!text.startsWith(_keyPrefix)) return null;
  final body = text.substring(_keyPrefix.length);
  final Uint8List bytes;
  try {
    bytes = base64Url.decode(base64Url.normalize(body));
  } on FormatException {
    return null;
  }
  if (bytes.length != 32) return null;
  return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
}

String? codeFromLink(String link) {
  const prefix = 'dnet:id/';
  if (!link.startsWith(prefix)) return null;
  final hex = link.substring(prefix.length);
  if (hex.isEmpty || hex.length.isOdd) return null;
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    bytes[i] = byte;
  }
  return '$_codePrefix${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The link that something the camera read stands for: a person's link
/// from a code, or a link that was written out as it is. Null if it is
/// neither.
String? linkFromCode(String scanned) {
  final text = scanned.trim();
  if (text.startsWith(_codePrefix)) {
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(
        base64Url.normalize(text.substring(_codePrefix.length)),
      );
    } on FormatException {
      return null;
    }
    if (bytes.isEmpty) return null;
    final hex = StringBuffer();
    for (final byte in bytes) {
      hex.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return 'dnet:id/$hex';
  }
  return _link.firstMatch(text)?.group(0);
}
