import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';

/// What a screen or pane shows while it has nothing in it: a picture or an
/// icon, a line or two of text, and anything else under them. It rises and
/// fades in once when it first appears, then stays still.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.body,
    this.image,
    this.icon,
    this.title,
    this.footer,
  });

  /// A picture to show at the top. Use [icon] for a plain icon instead.
  final Widget? image;
  final AppIconData? icon;
  final String? title;
  final String body;

  /// Shown under the text, such as a button or a list of keys.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?image,
          if (image == null && icon != null)
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(icon!, size: 28, color: AppColors.text2),
            ),
          if (image != null || icon != null) const SizedBox(height: 16),
          if (title != null) ...[
            Text(title!, textAlign: TextAlign.center, style: AppText.rowTitle),
            const SizedBox(height: 6),
          ],
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.base.copyWith(color: AppColors.text2),
          ),
          if (footer != null) ...[const SizedBox(height: 24), footer!],
        ],
      ),
    );
  }
}

/// Fades [child] in as it rises a few pixels and grows to full size, once,
/// when it is first built. Nothing moves where the system asks for less
/// motion.
class RiseIn extends StatelessWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      child: child,
      // The same widgets around the child at every step, so it is never
      // built anew.
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
          ),
        );
      },
    );
  }
}

/// Keys and what they do, one pair to a line, with each key drawn as a
/// small cap. For a PC, whose keyboard gets around the app.
class KeyHints extends StatelessWidget {
  const KeyHints({super.key, required this.hints});

  /// Each key, as written on it, and what it does.
  final List<(String, String)> hints;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (keys, does) in hints)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Text(does, style: AppText.detail14)),
                    const SizedBox(width: 24),
                    KeyCap(keys),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A key on the keyboard, such as "Ctrl+K", drawn as a small cap.
class KeyCap extends StatelessWidget {
  const KeyCap(this.keys, {super.key});

  final String keys;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          bottom: BorderSide(color: AppColors.line, width: 2),
        ),
      ),
      child: Text(keys, style: AppText.mono(12, color: AppColors.text)),
    );
  }
}
