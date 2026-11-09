import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import 'pressable.dart';

/// A reaction and its count. The user's own reaction is tinted and outlined
/// in the accent colour. The pill is 30 high inside a 44 high touch target.
class ReactionPill extends StatelessWidget {
  const ReactionPill({super.key, required this.reaction, required this.onTap});

  final Reaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mine = reaction.mine;
    final (icon, label) = switch (reaction.kind) {
      ReactionKind.heart => (
        AppIcons.heart,
        l10n.heartReaction(reaction.count),
      ),
      ReactionKind.agree => (
        AppIcons.check,
        l10n.agreeReaction(reaction.count),
      ),
      // An emoji is shown as itself.
      ReactionKind.emoji => (
        null,
        l10n.emojiReaction(reaction.emoji, reaction.count),
      ),
    };
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      selected: mine,
      focusRadius: BorderRadius.circular(15),
      child: SizedBox(
        height: kMinTouchTarget,
        child: Center(
          widthFactor: 1,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: mine ? AppColors.accentSoft : AppColors.raised,
              borderRadius: BorderRadius.circular(15),
              border: mine ? Border.all(color: AppColors.accent) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  AppIcon(
                    icon,
                    size: 14,
                    color: mine ? AppColors.accent : AppColors.text,
                  )
                else
                  Text(
                    reaction.emoji,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      fontFamily: AppFonts.emoji,
                      fontSize: 15,
                      height: 1.1,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  '${reaction.count}',
                  textScaler: TextScaler.noScaling,
                  style: AppText.base.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
