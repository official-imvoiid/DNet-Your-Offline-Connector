import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../design/tokens.dart';
import 'buttons.dart';
import 'feedback.dart';
import 'text_box.dart';

/// Asks for one line of text in a sheet. Returns what was typed, or null
/// if the sheet was closed without pressing the button.
///
/// [check] says what is wrong with an answer, or null if it will do. The
/// sheet stays open and shows what it said.
Future<String?> showAppPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String initial = '',
  String? body,
  String? Function(String text)? check,
}) => showAppSheet<String>(
  context,
  builder: (_) => _Prompt(
    title: title,
    label: label,
    action: action,
    initial: initial,
    body: body,
    check: check,
  ),
);

class _Prompt extends StatefulWidget {
  const _Prompt({
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
  State<_Prompt> createState() => _PromptState();
}

class _PromptState extends State<_Prompt> {
  late final _text = TextEditingController(text: widget.initial);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              widget.title,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (widget.body != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              widget.body!,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppTextBox(
          controller: _text,
          label: widget.label,
          hint: widget.label,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _done(),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              _problem!,
              style: AppText.base.copyWith(color: AppColors.red),
            ),
          ),
        ],
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
