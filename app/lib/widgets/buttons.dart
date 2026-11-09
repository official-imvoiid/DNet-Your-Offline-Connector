import 'package:flutter/material.dart' show Tooltip, TooltipTriggerMode;
import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';
import 'pressable.dart';

enum AppButtonKind {
  /// Accent fill. The main action on a screen.
  primary,

  /// Raised fill. Everything else.
  secondary,

  /// Green fill. Confirms something good, such as matching words.
  success,

  /// Red outline. Destructive actions.
  danger,

  /// Red text on nothing. A destructive action beside other buttons.
  dangerText,
}

/// A text button, with an optional leading icon.
///
/// Large buttons are 52 high with radius 14 and 16 px text. Anything shorter
/// is a compact button with radius 12 and 15 px text.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = AppButtonKind.secondary,
    this.height = 52,
    this.horizontalPadding = 18,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final AppButtonKind kind;
  final double height;
  final double horizontalPadding;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final large = height >= 52;
    final radius = BorderRadius.circular(
      large ? AppRadius.largeButton : AppRadius.smallButton,
    );
    final (background, foreground, weight) = switch (kind) {
      AppButtonKind.primary => (
        AppColors.accent,
        AppColors.accentInk,
        FontWeight.w700,
      ),
      AppButtonKind.secondary => (
        AppColors.raised,
        AppColors.text,
        FontWeight.w600,
      ),
      AppButtonKind.success => (
        AppColors.green,
        AppColors.greenInk,
        FontWeight.w700,
      ),
      AppButtonKind.danger => (null, AppColors.red, FontWeight.w700),
      AppButtonKind.dangerText => (null, AppColors.red, FontWeight.w600),
    };

    return Pressable(
      onTap: onTap,
      focusRadius: radius,
      pressedScale: 0.97,
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: kind == AppButtonKind.danger
              ? Border.all(color: AppColors.red)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: 18, color: foreground),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppText.base.copyWith(
                  color: foreground,
                  fontWeight: weight,
                  fontSize: large ? 16 : 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An icon-only button. The touch target is 44 by 44 unless [size] says more.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = kMinTouchTarget,
    this.iconSize = 22,
    this.color = AppColors.text,
    this.background,
    this.round = false,
    this.filled = false,
  });

  final AppIconData icon;

  /// Read out by screen readers. Icon buttons have no visible text.
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color color;
  final Color? background;

  /// A circle instead of a 12 px rounded square.
  final bool round;

  /// Fill the icon as well as stroking it.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(round ? size / 2 : 12);
    return HoverTip(
      message: label,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        focusRadius: radius,
        pressedScale: 0.92,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: background, borderRadius: radius),
          alignment: Alignment.center,
          child: AppIcon(icon, size: iconSize, color: color, filled: filled),
        ),
      ),
    );
  }
}

/// Shows [message] in a small box beside [child] while a mouse rests on
/// it, for controls with no words of their own. Touch is left alone: a
/// long press keeps whatever it already does. Screen readers already have
/// the words from the control itself, so the box is not read out.
class HoverTip extends StatelessWidget {
  const HoverTip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A tip needs somewhere to be drawn. What is drawn over the app, such
    // as a call, has nowhere, and goes without.
    if (message.isEmpty || Overlay.maybeOf(context) == null) return child;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      textStyle: AppText.base.copyWith(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: child,
    );
  }
}
