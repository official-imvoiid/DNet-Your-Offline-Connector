import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'buttons.dart';
import 'feedback.dart';
import 'link_text.dart';
import 'pressable.dart';
import 'text_box.dart';

/// The marks of [LinkText], looked for without drawing anything.
final _blockMarks = RegExp(
  r'^(?:#{1,6}[ \t]+\S|[ \t]*[-*+•][ \t]+\S|[ \t]*\d{1,9}[.)][ \t]+\S|>|```)',
  multiLine: true,
);
final _inlineMarks = RegExp(
  r'\*\*.+?\*\*|~~.+?~~|\|\|.+?\|\||`[^`\n]+`|\[[^\]\n]+\]\([^()\s]+\)'
  r'|(?<![\w*])\*(?![\s*]).+?(?<![\s*])\*(?![\w*])'
  r'|(?<![\w_])_(?![\s_]).+?(?<![\s_])_(?![\w_])',
);

/// Whether [text] has any of the marks a message can be written with,
/// such as **bold** or a list, so that it looks different once sent.
bool hasFormatting(String text) =>
    text.length <= 16000 &&
    (_blockMarks.hasMatch(text) || _inlineMarks.hasMatch(text));

/// [text] with its marks taken off, for a place that shows one plain
/// line, as the top of a screen or a preview in a list: "**Trail** day"
/// becomes "Trail day", and "[map](example.com)" becomes "map".
String plainText(String text) {
  if (!text.contains(RegExp(r'[*_~|`\[#>]'))) return text;
  return text
      .replaceAllMapped(
        RegExp(r'!?\[([^\]\n]+)\]\([^()\s]+\)'),
        (m) => m.group(1)!,
      )
      .replaceAll(RegExp(r'^```.*$', multiLine: true), '')
      .replaceAll(RegExp(r'^#{1,6}[ \t]+', multiLine: true), '')
      .replaceAll(RegExp(r'^>[ \t]?', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*|~~(.+?)~~|\|\|(.+?)\|\||`([^`\n]+)`'),
        (m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4)!,
      )
      .replaceAllMapped(
        RegExp(
          r'(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])'
          r'|(?<![\w_])_(?![\s_])(.+?)(?<![\s_])_(?![\w_])',
        ),
        (m) => m.group(1) ?? m.group(2)!,
      )
      .trim();
}

/// How [text] will look once it is sent or saved, under a "Preview"
/// line, with a way to see every mark that can be used.
class WritingPreview extends StatelessWidget {
  const WritingPreview({super.key, required this.text, this.margin});

  final String text;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(l10n.writingPreview, style: AppText.footnote),
                ),
              ),
              Pressable(
                onTap: () => showFormatHelp(context),
                semanticLabel: l10n.formatHelp,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Center(
                      widthFactor: 1,
                      child: ExcludeSemantics(
                        child: Text(
                          l10n.formatHelp,
                          style: AppText.detail.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 10),
              child: LinkText(text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every mark a message can be written with: what to type, and how it
/// looks.
Future<void> showFormatHelp(BuildContext context) => showAppSheet<void>(
  context,
  builder: (context) {
    final l10n = context.l10n;
    final samples = [
      ...l10n.formatSamples.split('\n'),
      '```\n${l10n.formatSampleCode}\n```',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(l10n.formatHelpTitle, style: AppText.rowTitle),
        ),
        const SizedBox(height: 6),
        Text(l10n.formatHelpBody, style: AppText.detail),
        const SizedBox(height: 8),
        for (final sample in samples)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    sample,
                    style: AppText.mono(13, color: AppColors.text2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: LinkText(sample)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(l10n.formatSafeNote, style: AppText.footnote),
      ],
    );
  },
);

/// Asks for words that may run to several lines and use the marks of a
/// message, such as a space's rules or welcome, and shows how they will
/// look as they are written. Returns what was written, or null if the
/// sheet was closed without pressing the button.
///
/// [check] says what is wrong with an answer, or null if it will do. The
/// sheet stays open and shows what it said.
Future<String?> showWritingPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String initial = '',
  String? body,
  String? Function(String text)? check,
}) => showAppSheet<String>(
  context,
  builder: (_) => _WritingPrompt(
    title: title,
    label: label,
    action: action,
    initial: initial,
    body: body,
    check: check,
  ),
);

class _WritingPrompt extends StatefulWidget {
  const _WritingPrompt({
    required this.title,
    required this.label,
    required this.action,
    required this.initial,
    required this.body,
    required this.check,
  });

  final String title;
  final String label;
  final String action;
  final String initial;
  final String? body;
  final String? Function(String text)? check;

  @override
  State<_WritingPrompt> createState() => _WritingPromptState();
}

class _WritingPromptState extends State<_WritingPrompt> {
  late final _text = TextEditingController(text: widget.initial)
    ..addListener(() => setState(() {}));
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final problem = widget.check?.call(_text.text);
    if (problem != null) {
      setState(() => _problem = problem);
    } else {
      Navigator.of(context).pop(_text.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = _text.text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(widget.title, style: AppText.rowTitle),
        ),
        if (widget.body case final body?) ...[
          const SizedBox(height: 6),
          Text(body, style: AppText.detail),
        ],
        const SizedBox(height: 12),
        AppTextBox(
          controller: _text,
          label: widget.label,
          fontSize: 16,
          height: 48,
          maxLines: 6,
        ),
        if (_problem case final problem?) ...[
          const SizedBox(height: 8),
          Text(problem, style: AppText.detail.copyWith(color: AppColors.red)),
        ],
        if (hasFormatting(text))
          WritingPreview(text: text, margin: const EdgeInsets.only(top: 10))
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: () => showFormatHelp(context),
              semanticLabel: l10n.formatHelp,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  child: ExcludeSemantics(
                    child: Text(
                      l10n.formatHelpHint,
                      style: AppText.detail.copyWith(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        AppButton(
          label: widget.action,
          kind: AppButtonKind.primary,
          onTap: _done,
        ),
      ],
    );
  }
}
