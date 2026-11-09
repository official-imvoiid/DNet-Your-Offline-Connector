import 'package:flutter/foundation.dart';

import 'models.dart';
import 'stickers.dart';

/// A pack of stickers the user made, in the order they put them.
@immutable
class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.stickers,
  });

  final String id;

  /// What the user called it. Empty for the pack made for them, which the
  /// screens call "Your stickers".
  final String name;
  final List<Sticker> stickers;
}

/// The user's stickers as they arranged them, and what the emoji picker
/// remembers. Kept in a [StickerVault]; read the first time it is asked
/// for.
///
/// Each sticker of the user's own is in exactly one of their packs. The
/// stickers the app comes with are a pack of their own that cannot be
/// changed. Favourites may be either kind.
class StickerBook {
  StickerBook(this._vault, {this.looseFolder});

  final StickerVault _vault;

  /// Where an older version of the app kept stickers as plain files.
  final String? looseFolder;

  /// The most packs, and the longest name one may have.
  static const mostPacks = 50;
  static const longestName = 40;

  /// How many emoji the picker remembers.
  static const mostRecent = 32;

  /// The most favourites.
  static const mostFavourites = 48;

  var _read = false;
  final _packs = <_Pack>[];
  final _favourites = <String>[];
  final _recent = <String>[];
  var _tone = 0;

  /// Each picture's hash, by id, so a sticker someone sent is known.
  final _hashes = <String, String>{};
  final _pictures = <String, Uint8List>{};

  void _ensureRead() {
    if (_read) return;
    _read = true;
    final (:book, :pictures) = _vault.read();
    final kept = pictures.toSet();
    final placed = <String>{};
    if (book != null) {
      for (final pack in book['packs'] as List? ?? const []) {
        if (pack case {
          'id': final String id,
          'name': final String name,
          'items': final List items,
        }) {
          final ids = [
            for (final item in items.whereType<String>())
              if (kept.contains(item) && placed.add(item)) item,
          ];
          _packs.add(_Pack(id, name, ids));
        }
      }
      if (book['hashes'] case final Map hashes) {
        for (final MapEntry(:key, :value) in hashes.entries) {
          if (key is String && value is String && placed.contains(key)) {
            _hashes[key] = value;
          }
        }
      }
      for (final key
          in (book['favourites'] as List? ?? const []).whereType<String>()) {
        if (_known(key) && !_favourites.contains(key)) _favourites.add(key);
      }
      if (book['emoji'] case {'recent': final List recent}) {
        _recent.addAll(recent.whereType<String>().take(mostRecent));
      }
      if (book['emoji'] case {'tone': final int tone}) {
        _tone = tone.clamp(0, 5);
      }
    }
    // A picture no pack holds was being kept when the app stopped, or its
    // pack was being deleted: it is let go.
    for (final id in kept.difference(placed)) {
      _vault.drop(id);
    }
    var changed = false;
    if (looseFolder case final folder?) {
      for (final image in takeLooseStickers(folder).reversed) {
        changed = _keep(image, null) || changed;
      }
    }
    for (final pack in _packs) {
      for (final id in pack.ids) {
        if (_hashes.containsKey(id)) continue;
        final image = _picture(id);
        if (image != null) _hashes[id] = stickerHash(image);
        changed = true;
      }
    }
    if (changed) _save();
  }

  bool _known(String key) => switch (key.split(':')) {
    ['app', final name] => builtInStickers.contains(name),
    ['own', final id] => _packs.any((p) => p.ids.contains(id)),
    _ => false,
  };

  void _save() {
    _vault.saveBook({
      'v': 1,
      'packs': [
        for (final pack in _packs)
          {'id': pack.id, 'name': pack.name, 'items': pack.ids},
      ],
      'hashes': _hashes,
      'favourites': _favourites,
      'emoji': {'recent': _recent, 'tone': _tone},
    });
  }

  Uint8List? _picture(String id) =>
      _pictures[id] ??= _vault.picture(id) ?? Uint8List(0);

  Sticker? _sticker(String key) => switch (key.split(':')) {
    ['app', final name] => Sticker.builtIn(name),
    ['own', final id] => switch (_picture(id)) {
      final image? when image.isNotEmpty => Sticker.own(image),
      _ => null,
    },
    _ => null,
  };

  /// The id a sticker of the user's own is kept under, if it is kept.
  String? _idOf(Uint8List image) {
    final hash = stickerHash(image);
    for (final MapEntry(:key, :value) in _hashes.entries) {
      if (value == hash && listEquals(_picture(key), image)) return key;
    }
    return null;
  }

  /// How the book names [sticker], or null for one of someone's own that
  /// the user has not kept.
  String? keyOf(Sticker sticker) {
    _ensureRead();
    return switch (sticker.image) {
      final image? => switch (_idOf(image)) {
        final id? => 'own:$id',
        null => null,
      },
      null => 'app:${sticker.name}',
    };
  }

  // Packs

  /// The user's own packs, in their order.
  List<StickerPack> get packs {
    _ensureRead();
    return [
      for (final pack in _packs)
        StickerPack(
          id: pack.id,
          name: pack.name,
          stickers: [for (final id in pack.ids) ?_sticker('own:$id')],
        ),
    ];
  }

  /// Every sticker of the user's own, pack by pack.
  List<Sticker> get mine => [for (final pack in packs) ...pack.stickers];

  /// The pack [sticker] is in, if the user keeps it.
  String? packOf(Sticker sticker) {
    final key = keyOf(sticker);
    if (key == null || !key.startsWith('own:')) return null;
    final id = key.substring(4);
    for (final pack in _packs) {
      if (pack.ids.contains(id)) return pack.id;
    }
    return null;
  }

  static String _cleanName(String name) {
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed.length > longestName
        ? trimmed.substring(0, longestName).trim()
        : trimmed;
  }

  /// Makes a new pack, last, and gives back its id. Null if there are as
  /// many as there may be.
  String? createPack(String name) {
    _ensureRead();
    if (_packs.length >= mostPacks) return null;
    final id = _newPackId();
    _packs.add(_Pack(id, _cleanName(name), []));
    _save();
    return id;
  }

  void renamePack(String id, String name) {
    _ensureRead();
    final pack = _pack(id);
    if (pack == null) return;
    pack.name = _cleanName(name);
    _save();
  }

  /// Deletes the pack and every sticker in it.
  void deletePack(String id) {
    _ensureRead();
    final pack = _pack(id);
    if (pack == null) return;
    _packs.remove(pack);
    for (final picture in pack.ids) {
      _forgetId(picture);
    }
    _save();
  }

  /// Moves the pack to [index] among the packs.
  void movePack(String id, int index) {
    _ensureRead();
    final pack = _pack(id);
    if (pack == null) return;
    _packs.remove(pack);
    _packs.insert(index.clamp(0, _packs.length), pack);
    _save();
  }

  /// Moves [sticker] to [index] in the pack [to], from wherever it was.
  /// Last if [index] is null.
  void moveSticker(Sticker sticker, String to, {int? index}) {
    final key = keyOf(sticker);
    final target = _pack(to);
    if (key == null || !key.startsWith('own:') || target == null) return;
    final id = key.substring(4);
    for (final pack in _packs) {
      pack.ids.remove(id);
    }
    target.ids.insert(
      (index ?? target.ids.length).clamp(0, target.ids.length),
      id,
    );
    _save();
  }

  String _newPackId() {
    var n = _packs.length;
    while (_packs.any((p) => p.id == 'p$n')) {
      n++;
    }
    return 'p$n';
  }

  _Pack? _pack(String id) {
    for (final pack in _packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  // Keeping

  /// Whether the user keeps [sticker]. One the app comes with, everyone
  /// has.
  bool holds(Sticker sticker) => sticker.isOwn ? keyOf(sticker) != null : true;

  /// Keeps [image] in the pack [packId], or the first pack, made if there
  /// is none. One already kept stays where it is. False if it cannot be
  /// kept.
  bool keep(Uint8List image, {String? packId}) {
    _ensureRead();
    if (!_keep(image, packId)) return false;
    _save();
    return true;
  }

  bool _keep(Uint8List image, String? packId) {
    if (image.isEmpty || image.length > maxStickerBytes) return false;
    if (_idOf(image) != null) return true;
    final pack = packId == null ? null : _pack(packId);
    final into = pack ?? (_packs.isEmpty ? null : _packs.first);
    if (into == null && _packs.length >= mostPacks) return false;
    final id = _vault.keep(image);
    if (id == null) return false;
    _pictures[id] = image;
    _hashes[id] = stickerHash(image);
    var target = into;
    if (target == null) {
      target = _Pack(_newPackId(), '', []);
      _packs.add(target);
    }
    target.ids.insert(0, id);
    return true;
  }

  /// Forgets a sticker of the user's own.
  void forget(Sticker sticker) {
    final key = keyOf(sticker);
    if (key == null || !key.startsWith('own:')) return;
    final id = key.substring(4);
    for (final pack in _packs) {
      pack.ids.remove(id);
    }
    _forgetId(id);
    _save();
  }

  void _forgetId(String id) {
    _favourites.remove('own:$id');
    _hashes.remove(id);
    _pictures.remove(id);
    _vault.drop(id);
  }

  // Favourites

  /// The favourites, in the user's order.
  List<Sticker> get favourites {
    _ensureRead();
    return [for (final key in _favourites) ?_sticker(key)];
  }

  bool isFavourite(Sticker sticker) {
    final key = keyOf(sticker);
    return key != null && _favourites.contains(key);
  }

  /// Makes [sticker] a favourite, first, or not one. A sticker of
  /// someone's own is kept first. False if it could not be.
  bool setFavourite(Sticker sticker, bool favourite) {
    _ensureRead();
    var key = keyOf(sticker);
    if (favourite && key == null) {
      if (!_keep(sticker.image!, null)) return false;
      key = keyOf(sticker);
    }
    if (key == null) return !favourite;
    _favourites.remove(key);
    if (favourite) {
      _favourites.insert(0, key);
      if (_favourites.length > mostFavourites) _favourites.removeLast();
    }
    _save();
    return true;
  }

  /// Moves a favourite to [index] among them.
  void moveFavourite(Sticker sticker, int index) {
    final key = keyOf(sticker);
    if (key == null || !_favourites.remove(key)) return;
    _favourites.insert(index.clamp(0, _favourites.length), key);
    _save();
  }

  // Emoji

  /// Emoji the user chose lately, newest first.
  List<String> get recentEmoji {
    _ensureRead();
    return List.unmodifiable(_recent);
  }

  void choseEmoji(String emoji) {
    _ensureRead();
    _recent
      ..remove(emoji)
      ..insert(0, emoji);
    if (_recent.length > mostRecent) _recent.removeLast();
    _save();
  }

  /// The skin tone the picker shows emoji in: 0 for none, 1 light to 5
  /// dark.
  int get skinTone {
    _ensureRead();
    return _tone;
  }

  set skinTone(int tone) {
    _ensureRead();
    _tone = tone.clamp(0, 5);
    _save();
  }

  /// Forgets everything held in memory, after the vault was erased, and
  /// any stickers an older version left as plain files.
  void reset() {
    if (looseFolder case final folder?) takeLooseStickers(folder);
    _read = false;
    _packs.clear();
    _favourites.clear();
    _recent.clear();
    _tone = 0;
    _hashes.clear();
    _pictures.clear();
  }
}

class _Pack {
  _Pack(this.id, this.name, this.ids);

  final String id;
  String name;
  final List<String> ids;
}
