import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/device_platform.dart';
import '../data/names.dart';
import '../data/safe_link.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';
import 'feedback.dart';

/// Someone a written @name may stand for: their key, so pressing the name
/// opens the right person even when two share it.
typedef MentionTarget = ({String key, String name});

/// Text written in a chat, a channel or a space's own words, with the
/// marks a message can be written with turned into styles.
///
/// Lines: `# Heading` (to `###`), `- item` or `* item`, `1. item`, and
/// `> quote`. A block of code between two lines of ```. Within a line:
/// `code`, **bold**, ~~struck out~~, ||spoiler||, *italic* or _italic_,
/// and links written out or as [words](link).
///
/// Nothing in the text can show a picture, run anything or fetch
/// anything: `![words](link)` is a link like any other, and HTML is shown
/// as it was typed. Pressing a link first says where it really goes, and
/// it opens only if the user then chooses to.
class LinkText extends StatefulWidget {
  const LinkText(
    this.text, {
    super.key,
    this.mentions = const [],
    this.people = const [],
    this.onMention,
    this.style,
    this.maxLines,
  });

  /// Set for a place with room for only so many lines, such as a channel's
  /// name in a list: the text is then read as one paragraph, with its
  /// marks within lines only, and cut off with an ellipsis.
  final int? maxLines;

  final String text;

  /// Names written as @name in the text, drawn in the accent colour.
  final List<String> mentions;

  /// Who each @name in [mentions] may be. A name two people share is told
  /// apart by the tag written after it, as in "@amber-tiger·4F2A".
  final List<MentionTarget> people;

  /// Called with a person's key when their @name is pressed.
  final ValueChanged<String>? onMention;

  /// The style the text starts from. The surrounding one if null.
  final TextStyle? style;

  @override
  State<LinkText> createState() => _LinkTextState();
}

/// A part of what was written that sits on its own: a paragraph, a
/// heading, a list item, a quote or a block of code. [start] is where it
/// starts in the text, so a spoiler keeps its place across redraws.
sealed class _Block {
  const _Block(this.text, this.start);
  final String text;
  final int start;
}

class _Paragraph extends _Block {
  const _Paragraph(super.text, super.start);
}

class _Heading extends _Block {
  const _Heading(this.level, super.text, super.start);
  final int level;
}

class _Item extends _Block {
  const _Item(this.marker, this.depth, super.text, super.start);

  /// "•", or the number as written, as "3.".
  final String marker;
  final int depth;
}

class _Quote extends _Block {
  const _Quote(super.text, super.start);
}

class _Code extends _Block {
  const _Code(super.text, super.start);
}

/// Text longer than this is shown as it was written, without marks, so a
/// huge message cannot slow the screen down.
const _longest = 16000;

/// Reads [text] into its blocks. Lines are only ever looked at once.
List<_Block> _blocks(String text) {
  final heading = RegExp(r'^(#{1,6})[ \t]+(.+)$');
  final bullet = RegExp(r'^([ \t]*)[-*+•][ \t]+(.+)$');
  final numbered = RegExp(r'^([ \t]*)(\d{1,9})([.)])[ \t]+(.+)$');
  final quote = RegExp(r'^>[ \t]?(.*)$');
  final blocks = <_Block>[];
  final lines = text.split('\n');
  final starts = <int>[];
  var at = 0;
  for (final line in lines) {
    starts.add(at);
    at += line.length + 1;
  }
  int depthOf(String indent) =>
      (indent.replaceAll('\t', '  ').length ~/ 2).clamp(0, 3);

  final paragraph = <String>[];
  var paragraphStart = 0;
  var quoteLine = -2;
  void endParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(_Paragraph(paragraph.join('\n'), paragraphStart));
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    // A block of code runs from a line starting ``` to the next one. One
    // that is never closed is not a block, and its marks are shown.
    if (trimmed.startsWith('```') &&
        !(trimmed.length > 6 && trimmed.endsWith('```'))) {
      final end = lines.indexWhere(
        (l) => l.trimLeft().startsWith('```'),
        i + 1,
      );
      if (end > i) {
        endParagraph();
        blocks.add(_Code(lines.sublist(i + 1, end).join('\n'), starts[i]));
        i = end;
        continue;
      }
    }
    if (heading.firstMatch(line) case final m?) {
      endParagraph();
      blocks.add(
        _Heading(m.group(1)!.length.clamp(1, 3), m.group(2)!, starts[i]),
      );
    } else if (bullet.firstMatch(line) case final m?) {
      endParagraph();
      blocks.add(_Item('•', depthOf(m.group(1)!), m.group(2)!, starts[i]));
    } else if (numbered.firstMatch(line) case final m?) {
      endParagraph();
      blocks.add(
        _Item(
          '${m.group(2)}${m.group(3)}',
          depthOf(m.group(1)!),
          m.group(4)!,
          starts[i],
        ),
      );
    } else if (quote.firstMatch(line) case final m?) {
      endParagraph();
      // Lines of a quote one after another are one quote.
      if (blocks.lastOrNull case final _Quote last when quoteLine == i - 1) {
        blocks[blocks.length - 1] = _Quote(
          '${last.text}\n${m.group(1)!}',
          last.start,
        );
      } else {
        blocks.add(_Quote(m.group(1)!, starts[i]));
      }
      quoteLine = i;
    } else if (line.trim().isEmpty) {
      endParagraph();
    } else {
      if (paragraph.isEmpty) paragraphStart = starts[i];
      paragraph.add(line);
    }
  }
  endParagraph();
  return blocks;
}

class _LinkTextState extends State<LinkText> {
  final _taps = <TapGestureRecognizer>[];

  /// Where each spoiler the user has tapped open starts in the text.
  final _opened = <int>{};

  /// The blocks of the text last drawn, kept until the text changes.
  String? _read;
  List<_Block> _parts = const [];

  /// The marks within a line: ```code```, `code`, [words](link), a link
  /// written out, **bold**, ~~struck out~~, ||spoiler||, and *italic* or
  /// _italic_. A link written out is taken whole, so the marks of
  /// italic cannot be found inside one. The marks themselves are not
  /// shown.
  static final _format = RegExp(
    r'```([^\n]+?)```'
    r'|`([^`\n]+)`'
    r'|!?\[([^\]\n]{1,300})\]\(([^()\s]{1,2000})\)'
    r'''|((?:https?://|www\.)[^\s<>"'`]+)'''
    r'|\*\*(.+?)\*\*'
    r'|~~(.+?)~~'
    r'|\|\|(.+?)\|\|'
    r'|(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])'
    r'|(?<![\w_])_(?![\s_])(.+?)(?<![\s_])_(?![\w_])',
    caseSensitive: false,
  );

  /// Punctuation that usually ends the sentence around a link rather than
  /// the link itself.
  static final _trailing = RegExp(r'[.,;:!?)\]}*_~|]+$');

  static const _linkStyle = TextStyle(
    color: AppColors.accent,
    decoration: TextDecoration.underline,
    decorationColor: AppColors.accent,
  );

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final tap = TapGestureRecognizer()..onTap = onTap;
    _taps.add(tap);
    return tap;
  }

  /// [plain], which starts at [base] in the text, with its marks turned
  /// into styles. Marks inside marks are read too, as **bold _and_ more**.
  List<InlineSpan> _inline(String plain, int base) {
    final l10n = context.l10n;
    final spans = <InlineSpan>[];
    final mono = AppText.mono(14).fontFamily;
    var from = 0;
    for (final match in _format.allMatches(plain)) {
      if (match.start < from) continue;
      if (match.start > from) {
        spans.addAll(_named(plain.substring(from, match.start)));
      }
      from = match.end;
      final at = base + match.start;
      if ((match.group(1) ?? match.group(2)) case final code?) {
        spans.add(
          TextSpan(
            text: code,
            style: TextStyle(
              fontFamily: mono,
              backgroundColor: AppColors.raised,
            ),
          ),
        );
      } else if (match.group(3) case final words?) {
        final target = match.group(4)!;
        final link =
            SafeLink.parse(target) ??
            (SafeLink.hasLink(target)
                ? SafeLink.parse('https://$target')
                : null);
        if (link == null) {
          // Not a web link: shown as it was written.
          spans.addAll(_named(match.group(0)!));
        } else {
          final tap = _tap(
            () => showLinkCheck(context, link.original, shownAs: words),
          );
          spans.add(
            TextSpan(
              style: _linkStyle,
              children: _pressedWith(_inline(words, at + 1), tap),
            ),
          );
        }
      } else if (match.group(5) case final written?) {
        final link = written.replaceFirst(_trailing, '');
        spans.add(
          TextSpan(
            text: link,
            recognizer: _tap(() => showLinkCheck(context, link)),
            style: _linkStyle,
          ),
        );
        // What was taken off the end is back where it was, as words.
        from = match.start + link.length;
      } else if (match.group(6) case final bold?) {
        spans.add(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w700),
            children: _inline(bold, at + 2),
          ),
        );
      } else if (match.group(7) case final struck?) {
        spans.add(
          TextSpan(
            style: const TextStyle(decoration: TextDecoration.lineThrough),
            children: _inline(struck, at + 2),
          ),
        );
      } else if (match.group(8) case final spoiler?) {
        if (_opened.contains(at)) {
          spans.add(TextSpan(children: _inline(spoiler, at + 2)));
        } else {
          spans.add(
            TextSpan(
              text: spoiler,
              recognizer: _tap(() => setState(() => _opened.add(at))),
              semanticsLabel: l10n.spoiler,
              style: const TextStyle(
                color: AppColors.text3,
                backgroundColor: AppColors.text3,
              ),
            ),
          );
        }
      } else if ((match.group(9) ?? match.group(10)) case final italic?) {
        spans.add(
          TextSpan(
            style: const TextStyle(fontStyle: FontStyle.italic),
            children: _inline(italic, at + 1),
          ),
        );
      }
    }
    if (from < plain.length) spans.addAll(_named(plain.substring(from)));
    return spans;
  }

  /// [spans] with every piece of text in them pressed by [tap]. A press
  /// goes to the piece of text under the finger, not to a span around it,
  /// so each piece needs it.
  static List<InlineSpan> _pressedWith(
    List<InlineSpan> spans,
    TapGestureRecognizer tap,
  ) => [
    for (final span in spans)
      if (span is TextSpan)
        TextSpan(
          text: span.text,
          style: span.style,
          semanticsLabel: span.semanticsLabel,
          recognizer: span.text == null ? null : tap,
          children: switch (span.children) {
            final children? => _pressedWith(children, tap),
            null => null,
          },
        )
      else
        span,
  ];

  /// [plain] with each @name the message calls on drawn in the accent
  /// colour. A name with its tag after it, as "@amber-tiger·4F2A", is
  /// taken with the tag.
  List<InlineSpan> _named(String plain) {
    if (widget.mentions.isEmpty || !plain.contains('@')) {
      return [TextSpan(text: plain)];
    }
    final lower = plain.toLowerCase();
    final marks = <(int, int, String?)>[];
    for (final name in widget.mentions) {
      final written = '@${name.toLowerCase()}';
      for (
        var at = lower.indexOf(written);
        at >= 0;
        at = lower.indexOf(written, at + 1)
      ) {
        var end = at + written.length;
        final tag = Names.tagAfter(plain, end);
        if (tag != null) end += tag.length + 1;
        marks.add((at, end, _keyOf(name, tag)));
      }
    }
    if (marks.isEmpty) return [TextSpan(text: plain)];
    // The longest name first where two start at the same place.
    marks.sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2),
    );
    final spans = <InlineSpan>[];
    var from = 0;
    for (final (start, end, key) in marks) {
      if (start < from) continue;
      if (start > from) spans.add(TextSpan(text: plain.substring(from, start)));
      final onMention = widget.onMention;
      spans.add(
        TextSpan(
          text: plain.substring(start, end),
          recognizer: key == null || onMention == null
              ? null
              : _tap(() => onMention(key)),
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      from = end;
    }
    if (from < plain.length) spans.add(TextSpan(text: plain.substring(from)));
    return spans;
  }

  /// The key of the person [name] stands for: the one whose tag is
  /// [tag], or else the only one with that name. Null for a role, for
  /// everyone, or for a name two people share with no tag to choose.
  String? _keyOf(String name, String? tag) {
    final lower = name.toLowerCase();
    final named = [
      for (final person in widget.people)
        if (person.name.toLowerCase() == lower) person,
    ];
    if (tag != null) {
      for (final person in named) {
        if (Names.tag(person.key) == tag.toUpperCase()) return person.key;
      }
    }
    return named.length == 1 ? named.single.key : null;
  }

  @override
  void dispose() {
    for (final tap in _taps) {
      tap.dispose();
    }
    super.dispose();
  }

  Widget _block(_Block block, TextStyle? base) {
    switch (block) {
      case _Paragraph(:final text, :final start):
        return Text.rich(TextSpan(children: _inline(text, start)), style: base);
      case _Heading(:final level, :final text, :final start):
        return Semantics(
          header: true,
          child: Text.rich(
            TextSpan(children: _inline(text, start)),
            style: (base ?? const TextStyle()).copyWith(
              fontSize: switch (level) {
                1 => 20,
                2 => 18,
                _ => 16,
              },
              fontWeight: level == 1 ? FontWeight.w800 : FontWeight.w700,
              height: 1.3,
            ),
          ),
        );
      case _Item(:final marker, :final depth, :final text, :final start):
        return Padding(
          padding: EdgeInsets.only(left: 16.0 * depth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 18),
                child: Text(marker, style: base),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text.rich(
                  TextSpan(children: _inline(text, start)),
                  style: base,
                ),
              ),
            ],
          ),
        );
      case _Quote(:final text, :final start):
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.line, width: 3)),
          ),
          child: Text.rich(
            TextSpan(children: _inline(text, start)),
            style: (base ?? const TextStyle()).copyWith(color: AppColors.text2),
          ),
        );
      case _Code(:final text):
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.raised,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(text, style: AppText.mono(13)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
    final text = widget.text;
    final style = widget.style;
    if (text.length > _longest) return Text(text, style: style);
    if (widget.maxLines case final lines?) {
      return Text.rich(
        TextSpan(children: _inline(text, 0)),
        style: style,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (_read != text) {
      _read = text;
      _parts = _blocks(text);
    }
    final parts = _parts;
    // One plain paragraph, as most messages are, is one piece of text.
    if (parts case [_Paragraph(:final text, :final start)]) {
      return Text.rich(TextSpan(children: _inline(text, start)), style: style);
    }
    if (parts.isEmpty) return Text(text, style: style);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0) const SizedBox(height: 4),
          _block(part, style),
        ],
      ],
    );
  }
}

/// Says where a link really goes and what is odd about it, then offers to
/// open it in the browser or copy it, with tracking taken off. [shownAs]
/// is the words it was written under, as in [words](link). Nothing is
/// opened unless the user presses Open.
Future<void> showLinkCheck(
  BuildContext context,
  String text, {
  String? shownAs,
}) {
  final link = SafeLink.parse(text);
  if (link == null) return Future.value();
  // Words that look like a link to somewhere else are a trick.
  final shown = shownAs == null
      ? null
      : SafeLink.find(shownAs).firstOrNull ??
            (SafeLink.hasLink(shownAs) ? 'https://${shownAs.trim()}' : null);
  final disguised =
      shown != null && SafeLink.parse(shown)?.domain != link.domain;
  return showAppSheet<void>(
    context,
    builder: (context) {
      final l10n = context.l10n;
      final warnings = {
        LinkWarning.lookalike: l10n.linkWarnLookalike,
        LinkWarning.hiddenName: l10n.linkWarnHiddenName,
        LinkWarning.numbersOnly: l10n.linkWarnNumbersOnly,
        LinkWarning.notPrivate: l10n.linkWarnNotPrivate,
      };
      Widget warning(String said) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppIcon(AppIcons.warning, size: 20, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                said,
                style: AppText.detail14.copyWith(color: AppColors.amber),
              ),
            ),
          ],
        ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(l10n.linkCheckTitle, style: AppText.rowTitle),
          ),
          const SizedBox(height: 6),
          Text(l10n.linkLeavesApp, style: AppText.detail),
          const SizedBox(height: 12),
          Text(l10n.linkGoesTo, style: AppText.detail),
          Text(
            link.domain,
            style: AppText.base.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(link.clean, style: AppText.mono(12, color: AppColors.text2)),
          if (link.removed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.linkTrackingRemoved(link.removed.length),
              style: AppText.detail,
            ),
          ],
          if (disguised)
            warning(l10n.linkWarnDisguised((shownAs ?? '').trim())),
          for (final found in link.warnings) warning(warnings[found]!),
          const SizedBox(height: 12),
          Text(l10n.linkOpenNote, style: AppText.footnote),
          const SizedBox(height: 14),
          AppButton(
            label: l10n.openLink,
            kind: AppButtonKind.primary,
            onTap: () async {
              final opened = await DevicePlatform.openLink(link.clean);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              if (!opened) showAppToast(context, l10n.linkNotOpened);
            },
          ),
          const SizedBox(height: 10),
          AppButton(
            label: l10n.copyCleanLink,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: link.clean));
              if (context.mounted) {
                Navigator.of(context).pop();
                showAppToast(context, l10n.webLinkCopied);
              }
            },
          ),
        ],
      );
    },
  );
}
