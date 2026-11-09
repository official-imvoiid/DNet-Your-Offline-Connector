import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'emoji_data.g.dart';

export 'emoji_data.g.dart' show emojiVersion;

/// The emoji the picker offers: every one Unicode lists, kept in the app
/// so nothing is fetched. They are drawn by the emoji font the app comes
/// with, so a flag is a flag on Windows too and a phone shows emoji newer
/// than itself.
enum EmojiGroup {
  smileys('😀'),
  people('👋'),
  nature('🐶'),
  food('🍔'),
  activities('⚽'),
  travel('🚗'),
  objects('💡'),
  symbols('❤️'),
  flags('🏁');

  const EmojiGroup(this.icon);

  /// The emoji its tab shows.
  final String icon;

  /// The group's emoji, each without a skin tone.
  List<EmojiEntry> get entries => _catalogue.groups[this]!;

  /// The same, as the emoji alone.
  List<String> get emoji => _catalogue.plain[this]!;
}

/// One emoji the picker offers, with what it is found by.
class EmojiEntry {
  EmojiEntry._(this.emoji, this.name, this.words, this.tones, this.group);

  /// The emoji with no skin tone.
  final String emoji;

  /// Its name in English, as Unicode gives it: "thumbs up".
  final String name;

  /// Other words it is found by, small letters.
  final List<String> words;

  /// The five skin tones it comes in, light to dark, or none.
  final List<String> tones;

  final EmojiGroup group;

  bool get hasTones => tones.isNotEmpty;

  /// This emoji in skin tone [tone]: 0 for none, 1 light to 5 dark.
  String inTone(int tone) =>
      tone <= 0 || tone > tones.length ? emoji : tones[tone - 1];

  /// How well [query] finds it: higher is better, zero is not at all.
  /// Every word of the query must start a word of the name or the words
  /// it is found by.
  int _match(List<String> query, String whole) {
    var score = 0;
    final lower = name.toLowerCase();
    if (lower == whole) return 1000;
    if (lower.startsWith(whole)) score += 300;
    for (final part in query) {
      var best = 0;
      for (final word in _nameWords) {
        if (word == part) {
          best = 100;
          break;
        }
        if (word.startsWith(part)) best = best < 60 ? 60 : best;
      }
      if (best < 100) {
        for (final word in words) {
          if (word == part) {
            best = best < 50 ? 50 : best;
          } else if (word.startsWith(part)) {
            best = best < 25 ? 25 : best;
          }
        }
      }
      if (best == 0) return 0;
      score += best;
    }
    return score;
  }

  late final List<String> _nameWords = [
    for (final word in name.toLowerCase().split(_split))
      if (word.isNotEmpty) word,
  ];
}

final _split = RegExp(r'[\s:,.!()“”"’]+');

/// The skin tones, as the modifier each adds. The first is none.
const skinToneSwatches = ['✋', '✋🏻', '✋🏼', '✋🏽', '✋🏾', '✋🏿'];

class _Catalogue {
  _Catalogue() {
    EmojiGroup? group;
    for (final line in const LineSplitter().convert(emojiData)) {
      if (line.isEmpty) continue;
      if (line.startsWith('@')) {
        group = EmojiGroup.values.byName(line.substring(1));
        groups[group] = [];
        continue;
      }
      final fields = line.split('\t');
      final entry = EmojiEntry._(
        fields[0],
        fields[1],
        fields.length > 2 && fields[2].isNotEmpty
            ? fields[2].toLowerCase().split('|')
            : const [],
        fields.length > 3 && fields[3].isNotEmpty
            ? fields[3].split(' ')
            : const [],
        group!,
      );
      groups[group]!.add(entry);
      byEmoji[entry.emoji] = entry;
      byEmoji[_bare(entry.emoji)] ??= entry;
      for (final (i, toned) in entry.tones.indexed) {
        byEmoji[toned] = entry;
        tones[toned] = i + 1;
      }
    }
    for (final MapEntry(:key, :value) in groups.entries) {
      plain[key] = [for (final entry in value) entry.emoji];
    }
  }

  final groups = <EmojiGroup, List<EmojiEntry>>{};
  final plain = <EmojiGroup, List<String>>{};
  final byEmoji = <String, EmojiEntry>{};
  final tones = <String, int>{};
}

/// Read the first time an emoji is asked for, then kept.
final _catalogue = _Catalogue();

String _bare(String emoji) => emoji.replaceAll('\u{FE0F}', '');

/// Every emoji the picker offers, without skin tones, in order.
Iterable<EmojiEntry> get allEmoji =>
    EmojiGroup.values.expand((group) => group.entries);

/// The entry for [emoji], in any skin tone, or null if the picker does not
/// offer it.
EmojiEntry? emojiEntry(String emoji) =>
    _catalogue.byEmoji[emoji] ?? _catalogue.byEmoji[_bare(emoji)];

/// The skin tone [emoji] is in: 0 for none, 1 light to 5 dark.
int skinToneOf(String emoji) => _catalogue.tones[emoji] ?? 0;

/// The emoji [query] finds by name or by the words they are known by, the
/// best first. An emoji typed in finds itself.
List<EmojiEntry> searchEmoji(String query, {int most = 300}) {
  final whole = query.trim().toLowerCase();
  if (whole.isEmpty) return const [];
  if (emojiEntry(whole) case final entry?) return [entry];
  final parts = [
    for (final part in whole.split(_split))
      if (part.isNotEmpty) part,
  ];
  if (parts.isEmpty) return const [];
  final found = <(int, int, EmojiEntry)>[];
  var order = 0;
  for (final entry in allEmoji) {
    final score = entry._match(parts, whole);
    if (score > 0) found.add((score, order, entry));
    order++;
  }
  found.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
  return [for (final (_, _, entry) in found.take(most)) entry];
}

/// The emoji most people reach for, offered first for a reaction.
const quickReactions = ['👍', '😂', '😮', '😢', '🙏', '🔥'];

/// Whether [text] is one emoji and nothing else. The same rule the core
/// keeps to for reactions, so whatever the app offers it also takes.
bool isOneEmoji(String text) {
  if (text.isEmpty || utf8.encode(text).length > 32) return false;
  final runes = text.runes.toList();
  final keycap = runes.last == 0x20E3;
  var pictures = 0;
  var afterJoin = false;
  var afterFlagHalf = false;
  for (final code in runes) {
    if (code == 0x200D) {
      if (pictures == 0 || afterJoin) return false;
      afterJoin = true;
      continue;
    }
    final mark =
        code == 0xFE0F ||
        code == 0x20E3 ||
        (code >= 0x1F3FB && code <= 0x1F3FF) ||
        (code >= 0xE0020 && code <= 0xE007F);
    if (mark) {
      if (pictures == 0) return false;
      continue;
    }
    final flagHalf = code >= 0x1F1E6 && code <= 0x1F1FF;
    final picture = switch (code) {
      0x23 || 0x2A || >= 0x30 && <= 0x39 => keycap && pictures == 0,
      0xA9 || 0xAE || 0x203C || 0x2049 || 0x2122 || 0x2139 => true,
      >= 0x2194 && <= 0x21AA || >= 0x231A && <= 0x23FF || 0x24C2 => true,
      >= 0x25AA && <= 0x25FE || >= 0x2600 && <= 0x27BF => true,
      >= 0x2934 && <= 0x2935 || >= 0x2B05 && <= 0x2B55 => true,
      0x3030 || 0x303D || 0x3297 || 0x3299 => true,
      >= 0x1F000 && <= 0x1FAFF => true,
      _ => false,
    };
    final joined = afterJoin || (flagHalf && afterFlagHalf);
    if (!picture || (pictures > 0 && !joined)) return false;
    afterFlagHalf = flagHalf && !afterFlagHalf;
    afterJoin = false;
    pictures++;
  }
  return pictures > 0 && !afterJoin;
}

/// [emoji] as a reaction can carry it. A few emoji in a skin tone are too
/// long for a reaction; they react without the tone.
String asReaction(String emoji) {
  if (isOneEmoji(emoji)) return emoji;
  return emojiEntry(emoji)?.emoji ?? emoji;
}

/// The most emoji a message may be and still be shown large, as chat apps
/// show a message of only a few emoji.
const maxBigEmoji = 3;

/// How many emoji [text] is, if it is nothing but a few emoji (spaces
/// between them aside). Zero if it has anything else in it.
int bigEmojiCount(String text) {
  final shown = [
    for (final part in text.trim().characters)
      if (part.trim().isNotEmpty) part,
  ];
  if (shown.isEmpty || shown.length > maxBigEmoji) return 0;
  // Any emoji the picker offers, even one too long for a reaction.
  bool big(String part) => isOneEmoji(part) || emojiEntry(part) != null;
  return shown.every(big) ? shown.length : 0;
}
