/// Suggested names for someone who does not want to pick their own, such as
/// "red-falcon". They are only a starting point: a name may be anything.
abstract final class Names {
  static const _adjectives = [
    'amber',
    'brave',
    'calm',
    'clever',
    'copper',
    'gentle',
    'golden',
    'green',
    'quiet',
    'red',
    'silver',
    'swift',
    'teal',
    'violet',
    'warm',
    'wild',
  ];
  static const _animals = [
    'badger',
    'crane',
    'falcon',
    'finch',
    'fox',
    'hare',
    'heron',
    'ibis',
    'kite',
    'lynx',
    'otter',
    'owl',
    'panda',
    'robin',
    'tiger',
    'wren',
  ];

  /// [pick] returns a number below its argument, so callers can pass
  /// `Random().nextInt`.
  static String random(int Function(int max) pick) =>
      '${_adjectives[pick(_adjectives.length)]}-'
      '${_animals[pick(_animals.length)]}';

  // Names are not unique: anyone may pick "amber-tiger". Where two people
  // with the same name are shown together, each also gets a short tag
  // made from their key, the same on every device: "amber-tiger · 4F2A".

  /// The short tag for the person with [key]: its first four letters, in
  /// capitals.
  static String tag(String key) =>
      (key.length > 4 ? key.substring(0, 4) : key).toUpperCase();

  /// [name] with the tag of [key] after it.
  static String tagged(String name, String key) => '$name · ${tag(key)}';

  /// What goes between a written @name and its tag: "@amber-tiger·4F2A".
  static const tagMark = '·';

  /// The tag written as "·4F2A" at [at] in [text], without the mark, or
  /// null if there is none there.
  static String? tagAfter(String text, int at) {
    if (at + 5 > text.length || text[at] != tagMark) return null;
    final tag = text.substring(at + 1, at + 5);
    if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(tag)) return null;
    // "·4F2Ab" is a longer word, not a tag.
    if (at + 5 < text.length && RegExp(r'[\w]').hasMatch(text[at + 5])) {
      return null;
    }
    return tag;
  }

  /// The names, in small letters, that more than one of [people] go by.
  /// [mine] is the user's own, which counts as one more.
  static Set<String> shared(
    Iterable<({String key, String name})> people, {
    String? mine,
  }) {
    final seen = <String, String>{};
    final twice = <String>{};
    if (mine != null && mine.trim().isNotEmpty) {
      seen[mine.trim().toLowerCase()] = '';
    }
    for (final person in people) {
      final name = person.name.trim().toLowerCase();
      if (name.isEmpty) continue;
      final before = seen[name];
      if (before != null && before != person.key) twice.add(name);
      seen.putIfAbsent(name, () => person.key);
    }
    return twice;
  }

  /// What to call [name], with [key]: tagged if [shared] has the name.
  static String shown(String name, String key, Set<String> shared) =>
      shared.contains(name.trim().toLowerCase()) ? tagged(name, key) : name;
}
