import 'package:flutter/material.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';

/// A single-line text field on a surface coloured box.
class AppTextBox extends StatefulWidget {
  const AppTextBox({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.height = 52,
    this.fontSize = 17,
    this.horizontalPadding = 16,
    this.outlined = true,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.obscure = false,
    this.maxLines = 1,
    this.autofocus = false,
  });

  /// Puts the cursor in the box as soon as it appears, such as a search
  /// box the user has just asked for.
  final bool autofocus;

  /// More than one lets the box grow to that many lines as text is
  /// written, for words such as a space's rules.
  final int maxLines;

  final TextEditingController controller;

  /// What the field is for, read out by screen readers.
  final String label;
  final String? hint;
  final AppIconData? icon;
  final double height;
  final double fontSize;
  final double horizontalPadding;

  /// Draws the 1 px line around the box.
  final bool outlined;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  /// Shows dots instead of what is typed, for a passcode.
  final bool obscure;

  @override
  State<AppTextBox> createState() => _AppTextBoxState();
}

class _AppTextBoxState extends State<AppTextBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    // Asked for, so it takes the cursor even from another pane, which
    // autofocus alone would leave alone.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppText.base.copyWith(fontSize: widget.fontSize);
    // The field itself is as tall as the box, so all of the box is the
    // touch target. The 1 px border counts towards the height.
    final fieldPadding = (widget.height - 2 - widget.fontSize * 1.4) / 2;
    final lines = widget.obscure ? 1 : widget.maxLines;
    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction:
          widget.textInputAction ??
          (lines > 1 ? TextInputAction.newline : null),
      keyboardType: lines > 1 ? TextInputType.multiline : null,
      minLines: 1,
      maxLines: lines,
      obscureText: widget.obscure,
      enableSuggestions: !widget.obscure,
      autocorrect: !widget.obscure,
      cursorColor: AppColors.accent,
      style: style,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: fieldPadding),
        hintText: widget.hint,
        hintStyle: style.copyWith(color: AppColors.text3),
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.largeButton),
        border: Border.all(
          color: _focus.hasFocus
              ? AppColors.accent
              : widget.outlined
              ? AppColors.line
              : AppColors.surface,
        ),
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            AppIcon(widget.icon!, size: 18, color: AppColors.text2),
            const SizedBox(width: 12),
          ],
          Expanded(
            // A hint already names the field for screen readers.
            child: widget.hint == null
                ? Semantics(label: widget.label, child: field)
                : field,
          ),
        ],
      ),
    );
  }
}
