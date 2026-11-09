import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/core_bridge.dart';
import 'image_bounds.dart';
import 'models.dart';

/// The stickers the app comes with, drawn for it by tool/gen_stickers.py.
/// A sticker is sent by its name, so a name, once shipped, keeps meaning
/// the same picture.
const builtInStickers = [
  'hello',
  'thanks',
  'lol',
  'love',
  'wow',
  'sad',
  'angry',
  'cool',
  'sleepy',
  'party',
  'ok',
  'cat',
];

/// Where a sticker the app comes with is kept, or null for a name this
/// copy of the app does not have.
String? stickerAsset(String name) =>
    builtInStickers.contains(name) ? 'assets/stickers/$name.png' : null;

/// The most a sticker of the user's own may be, in bytes. It travels
/// inside the message, as a profile photo does. The core holds to it too.
const maxStickerBytes = 32 * 1024;

/// What the core is told a sticker is.
Map<String, Object?> stickerToWire(Sticker sticker) => switch (sticker.image) {
  final image? => {'image': _hexOf(image)},
  null => {'name': sticker.name},
};

/// A sticker as the core describes it, or null if it is not one.
Sticker? stickerFromWire(Object? wire) => switch (wire) {
  // A sticker of someone's own came from their device. One that claims
  // a huge size is not decoded: see image_bounds.dart.
  {'image': final String hex} => switch (_bytesOfHex(hex)) {
    final bytes? when soundImage(bytes) => Sticker.own(bytes),
    _ => null,
  },
  {'name': final String name} when name.isNotEmpty => Sticker.builtIn(name),
  _ => null,
};

String _hexOf(Uint8List bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

Uint8List? _bytesOfHex(String hex) {
  if (hex.isEmpty || hex.length.isOdd) return null;
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    bytes[i] = byte;
  }
  return bytes;
}

/// Makes a sticker from the picture or GIF at [path]: the whole picture,
/// not cut to a square, small enough to travel in a message. A GIF keeps
/// moving, with fewer frames if it has to, and a picture with see-through
/// parts keeps them. Null if it cannot be read or made small enough.
Future<Uint8List?> prepareSticker(String path) =>
    Isolate.run(() => prepareStickerBytes(File(path).readAsBytesSync()));

/// The same, from the picture's bytes.
Uint8List? prepareStickerBytes(Uint8List bytes) {
  final isGif =
      bytes.length > 6 && String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF';
  if (isGif) {
    final moving = img.decodeGif(bytes);
    if (moving == null) return null;
    for (final size in const [192, 160, 128, 96]) {
      final small = _fitted(moving, size);
      for (var step = 1; step <= 8; step *= 2) {
        final out = img.encodeGif(_everyNth(small, step));
        if (out.length <= maxStickerBytes) return out;
      }
    }
    return null;
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final picture = img.Image.from(decoded, noAnimation: true);
  if (_seeThrough(picture)) {
    // A photo with see-through parts, such as one with its background cut
    // out, is too big as it is: with fewer shades it stays sharp instead.
    for (final size in const [256, 224, 192, 160, 128, 96]) {
      final small = _clearHidden(_fitted(picture, size));
      for (final bits in const [8, 6, 5]) {
        final out = img.encodePng(_fewerShades(small, bits), level: 9);
        if (out.length <= maxStickerBytes) return out;
      }
    }
    return null;
  }
  for (final size in const [256, 192, 128]) {
    final small = _fitted(picture, size);
    for (final quality in const [85, 75, 65, 55]) {
      final out = img.encodeJpg(small, quality: quality);
      if (out.length <= maxStickerBytes) return out;
    }
  }
  return null;
}

/// No bigger than [size] either way, the same shape as before.
img.Image _fitted(img.Image picture, int size) {
  if (picture.width <= size && picture.height <= size) return picture;
  return picture.width >= picture.height
      ? img.copyResize(
          picture,
          width: size,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          picture,
          height: size,
          interpolation: img.Interpolation.average,
        );
}

/// The picture with nothing where it cannot be seen, which costs nothing
/// to keep.
img.Image _clearHidden(img.Image picture) {
  final out = img.Image.from(picture);
  for (final pixel in out) {
    if (pixel.a == 0) {
      pixel
        ..r = 0
        ..g = 0
        ..b = 0;
    }
  }
  return out;
}

/// The picture with [bits] of each colour kept, and its see-through parts
/// in sixteen steps. Eight keeps it as it is.
img.Image _fewerShades(img.Image picture, int bits) {
  if (bits >= 8) return picture;
  final out = img.Image.from(picture);
  final step = 1 << (8 - bits);
  num cut(num value, int by) =>
      math.min(255, (value ~/ by) * by + (value >= by ? by ~/ 2 : 0));
  for (final pixel in out) {
    pixel
      ..r = cut(pixel.r, step)
      ..g = cut(pixel.g, step)
      ..b = cut(pixel.b, step)
      ..a = pixel.a == 255 ? 255 : cut(pixel.a, 16);
  }
  return out;
}

/// Whether any of the picture can be seen through.
bool _seeThrough(img.Image picture) {
  if (!picture.hasAlpha) return false;
  for (final pixel in picture) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
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

/// A name for a picture made from the picture itself, so the same one is
/// known again. FNV-1a, 64 bits: not for secrets, only to tell pictures
/// apart.
String stickerHash(Uint8List image) {
  var hash = 0xcbf29ce484222325;
  for (final byte in image) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  String half(int bits) => bits.toRadixString(16).padLeft(8, '0');
  return '${half(hash >>> 32)}${half(hash & 0xFFFFFFFF)}';
}

/// Where the user's own stickers are kept, and the book that arranges
/// them. On a device this is the core's vault, sealed like everything else
/// the app keeps.
abstract class StickerVault {
  /// The book as last saved, if ever, and the id of every picture kept.
  ({Map<String, Object?>? book, List<String> pictures}) read();

  void saveBook(Map<String, Object?> book);

  /// Keeps [image] and gives back its id, or null if it cannot be kept.
  String? keep(Uint8List image);

  /// The picture kept as [id], or null if there is none.
  Uint8List? picture(String id);

  void drop(String id);
}

/// The core's vault.
class CoreStickerVault implements StickerVault {
  CoreStickerVault(this._bridge);

  final CoreBridge _bridge;

  @override
  ({Map<String, Object?>? book, List<String> pictures}) read() {
    try {
      final reply = _bridge.call({'op': 'sticker_book'});
      if (reply case {'book': final book, 'pictures': final List pictures}) {
        return (
          book: book is Map<String, Object?> ? book : null,
          pictures: pictures.whereType<String>().toList(),
        );
      }
    } on CoreException {
      // Not open yet, or unreadable: nothing is kept.
    }
    return (book: null, pictures: const []);
  }

  @override
  void saveBook(Map<String, Object?> book) {
    try {
      _bridge.call({'op': 'sticker_book_save', 'book': book});
    } on CoreException {
      // Kept in memory until the next change saves it.
    }
  }

  @override
  String? keep(Uint8List image) {
    try {
      final reply = _bridge.call({
        'op': 'sticker_keep',
        'image': _hexOf(image),
      });
      return switch (reply) {
        {'id': final String id} => id,
        _ => null,
      };
    } on CoreException {
      return null;
    }
  }

  @override
  Uint8List? picture(String id) {
    try {
      return switch (_bridge.call({'op': 'sticker_picture', 'id': id})) {
        {'image': final String hex} => _bytesOfHex(hex),
        _ => null,
      };
    } on CoreException {
      return null;
    }
  }

  @override
  void drop(String id) {
    try {
      _bridge.call({'op': 'sticker_drop', 'id': id});
    } on CoreException {
      // Already gone, or tidied the next time the book is read.
    }
  }
}

/// Kept in memory only, where there is no vault: the design kit.
class MemoryStickerVault implements StickerVault {
  Map<String, Object?>? _book;
  final _pictures = <String, Uint8List>{};
  var _next = 0;

  @override
  ({Map<String, Object?>? book, List<String> pictures}) read() =>
      (book: _book, pictures: _pictures.keys.toList());

  @override
  void saveBook(Map<String, Object?> book) => _book = book;

  @override
  String? keep(Uint8List image) {
    if (image.isEmpty || image.length > maxStickerBytes) return null;
    final id = (_next++).toRadixString(16).padLeft(32, '0');
    _pictures[id] = image;
    return id;
  }

  @override
  Uint8List? picture(String id) => _pictures[id];

  @override
  void drop(String id) => _pictures.remove(id);
}

/// Stickers an older version of the app kept as plain files in [folder].
/// They are read once, to be moved into the vault, and the folder is
/// deleted.
List<Uint8List> takeLooseStickers(String folder) {
  final dir = Directory(folder);
  if (!dir.existsSync()) return const [];
  try {
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final found = [
      for (final file in files)
        if (file.lengthSync() <= maxStickerBytes) file.readAsBytesSync(),
    ];
    dir.deleteSync(recursive: true);
    return found;
  } on FileSystemException {
    return const [];
  }
}
