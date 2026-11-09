/// What can be said about a web link someone shared, before the user
/// does anything with it. Nothing here goes online: links are never
/// fetched or previewed.
library;

/// Something about a link the user should know before using it.
enum LinkWarning {
  /// The name uses letters from another alphabet that look like ordinary
  /// ones, as in a fake "paypal" written with a Cyrillic "а".
  lookalike,

  /// Words before an @ look like the site but are not where it goes, as
  /// in "bank.com@evil.example".
  hiddenName,

  /// The address is only numbers, with no name to recognise.
  numbersOnly,

  /// It starts with http://, so what is sent can be read on the way.
  notPrivate,
}

class SafeLink {
  const SafeLink._({
    required this.original,
    required this.clean,
    required this.domain,
    required this.removed,
    required this.warnings,
  });

  final String original;

  /// The link with tracking taken off.
  final String clean;

  /// Where the link really goes, in lower case.
  final String domain;

  /// The names of the tracking parts taken off.
  final List<String> removed;
  final List<LinkWarning> warnings;

  static final _link = RegExp(
    r'''(?:https?://|www\.)[^\s<>"'`]+''',
    caseSensitive: false,
  );

  /// Punctuation that usually ends the sentence around a link rather than
  /// the link itself.
  static final _trailing = RegExp(r'[.,;:!?)\]}]+$');

  /// Query parts that only say where a link was clicked from.
  static const _tracking = {
    'fbclid',
    'gclid',
    'dclid',
    'gbraid',
    'wbraid',
    'msclkid',
    'yclid',
    'igshid',
    'mc_cid',
    'mc_eid',
    'mkt_tok',
    '_hsenc',
    '_hsmi',
    'ref_src',
    'si',
  };

  /// Every web link in [text], in order.
  static List<String> find(String text) => [
    for (final match in _link.allMatches(text))
      match.group(0)!.replaceFirst(_trailing, ''),
  ];

  /// Whether [text] has a link in it, in any form one can be written:
  /// with a scheme ("https://", "ftp://"), starting "www.", a DNet invite,
  /// or a bare name such as "example.com", which is also what a markdown
  /// link "[words](example.com)" points at. An e-mail address is not a
  /// link. It is how a channel's "No links from members" is kept, and the
  /// core checks the same way (`has_link` in core/src/space.rs), so what
  /// the app lets through the core does too.
  static bool hasLink(String text) {
    final lower = text.toLowerCase();
    if (const ['www.', 'dnet:space/', 'dnet:invite/'].any(lower.contains)) {
      return true;
    }
    // A scheme is letters just before "://".
    for (
      var at = lower.indexOf('://');
      at >= 0;
      at = lower.indexOf('://', at + 3)
    ) {
      if (at > 0 && _asciiLetter(lower.codeUnitAt(at - 1))) return true;
    }
    return _hasBareName(text);
  }

  static bool _asciiLetter(int c) =>
      (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
  static bool _asciiDigit(int c) => c >= 0x30 && c <= 0x39;

  /// The endings of web names that are not two letters, as the ones of
  /// countries are. Any two letters count. The same as the core's.
  static const _endings = {
    'com', 'net', 'org', 'edu', 'gov', 'mil', 'int', 'info', 'biz', 'name', //
    'pro', 'mobi', 'app', 'dev', 'page', 'xyz', 'online', 'site', 'store',
    'shop', 'link', 'click', 'top', 'club', 'live', 'news', 'blog', 'tech',
    'cloud', 'zip', 'mov', 'art', 'wiki', 'fun', 'space', 'website', 'email',
    'life', 'world', 'today', 'network', 'digital', 'social', 'media',
    'video', 'stream', 'chat', 'games', 'game', 'bet', 'win', 'vip', 'icu',
    'cyou', 'sbs', 'cfd', 'buzz', 'rest', 'bond', 'lol', 'monster', 'quest',
    'run', 'onion', 'lat', 'cam', 'xxx', 'porn', 'sex', 'coop', 'aero',
    'museum', 'travel', 'asia',
  };

  /// Whether [text] has a web name in it with no scheme, as "example.com".
  /// Runs of letters, digits, dots and dashes are looked at; anything not
  /// ASCII counts as a letter, so the app and the core cut the text the
  /// same way.
  static bool _hasBareName(String text) {
    bool joins(int c) =>
        c > 0x7f || _asciiLetter(c) || _asciiDigit(c) || c == 0x2e || c == 0x2d;
    int? before;
    final run = StringBuffer();
    for (final c in [...text.runes, 0x20]) {
      if (joins(c)) {
        run.writeCharCode(c);
        continue;
      }
      if (run.isNotEmpty) {
        // After an @ it is an e-mail address, or someone's name.
        if (before != 0x40 && _isWebName(run.toString())) return true;
        run.clear();
      }
      before = c;
    }
    return false;
  }

  static bool _isWebName(String run) {
    final trimmed = run.replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
    final labels = trimmed.split('.');
    if (labels.length < 2 ||
        labels.any((label) => label.replaceAll('-', '').isEmpty)) {
      return false;
    }
    final end = labels.last;
    final lower = end.toLowerCase();
    if (lower.startsWith('xn--') && lower.length > 4) return true;
    if (!end.codeUnits.every(_asciiLetter)) return false;
    // "home.It was late" is a missed space, not a web name: an ending
    // written with a capital and then small letters does not count.
    final first = end.codeUnitAt(0);
    if (first >= 0x41 &&
        first <= 0x5a &&
        end.codeUnits.skip(1).any((c) => c >= 0x61 && c <= 0x7a)) {
      return false;
    }
    return lower.length == 2 || _endings.contains(lower);
  }

  /// Reads [text] as a web link. Null if it is not one.
  static SafeLink? parse(String text) {
    var raw = text.trim();
    // "www.example.com" goes where "https://www.example.com" does.
    if (raw.toLowerCase().startsWith('www.')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    final domain = uri.host.toLowerCase();
    final warnings = <LinkWarning>[];
    // Dart turns some lookalike letters into xn-- names and leaves others
    // as they were written, so both are looked at.
    final written = raw.split('://').last.split(RegExp('[/?#]')).first;
    if (domain.split('.').any((part) => part.startsWith('xn--')) ||
        written.runes.any((r) => r > 0x7f)) {
      warnings.add(LinkWarning.lookalike);
    }
    if (uri.userInfo.isNotEmpty) warnings.add(LinkWarning.hiddenName);
    if (RegExp(r'^[0-9.]+$').hasMatch(domain) || domain.contains(':')) {
      warnings.add(LinkWarning.numbersOnly);
    }
    if (uri.isScheme('http')) warnings.add(LinkWarning.notPrivate);

    final removed = <String>[];
    final kept = <String>[];
    if (uri.query.isNotEmpty) {
      for (final part in uri.query.split('&')) {
        final name = Uri.decodeQueryComponent(part.split('=').first);
        if (name.toLowerCase().startsWith('utm_') ||
            _tracking.contains(name.toLowerCase())) {
          removed.add(name);
        } else {
          kept.add(part);
        }
      }
    }
    final clean = uri
        .replace(query: kept.join('&'))
        .toString()
        .replaceFirst(RegExp(r'\?$'), '');
    return SafeLink._(
      original: raw,
      clean: removed.isEmpty ? raw : clean,
      domain: domain,
      removed: removed,
      warnings: warnings,
    );
  }
}
