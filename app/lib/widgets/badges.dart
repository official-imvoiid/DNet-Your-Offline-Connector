import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';

enum ChipTone { neutral, amber, green, accent }

/// A small label: 12 px, weight 600, radius 8.
class AppChip extends StatelessWidget {
  const AppChip(
    this.label, {
    super.key,
    this.tone = ChipTone.neutral,
    this.icon,
  });

  final String label;
  final ChipTone tone;
  final AppIconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      ChipTone.neutral => (AppColors.raised, AppColors.text2),
      ChipTone.amber => (AppColors.amberSoft, AppColors.amber),
      ChipTone.green => (AppColors.greenSoft, AppColors.green),
      ChipTone.accent => (AppColors.accentSoft, AppColors.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppText.base.copyWith(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The accent pill that counts unread messages.
class CountBadge extends StatelessWidget {
  const CountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.unreadCount(count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          '$count',
          style: AppText.base.copyWith(
            color: AppColors.accentInk,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// An @ beside a channel where someone called on the user in a message
/// they have not read.
class MentionBadge extends StatelessWidget {
  const MentionBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.mentionedYouCount(count),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          border: Border.all(color: AppColors.accent),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(
          '@',
          style: AppText.base.copyWith(
            color: AppColors.accent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The green shield beside the name of a verified person.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) {
    return AppIcon(
      AppIcons.verified,
      size: size,
      color: AppColors.green,
      semanticLabel: context.l10n.verified,
    );
  }
}

/// What a member's status is called, as the user reads it.
String statusName(AppLocalizations l10n, MemberStatus status) =>
    switch (status) {
      MemberStatus.online => l10n.statusOnline,
      MemberStatus.idle => l10n.statusIdle,
      MemberStatus.dnd => l10n.statusDnd,
      MemberStatus.invisible => l10n.statusInvisible,
      MemberStatus.offline => l10n.statusOffline,
    };

/// How a member says they are, as a small dot: green online, amber idle,
/// red do not disturb, and a grey ring for invisible or offline. Always
/// shown next to its name in words, so colour is never all there is.
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 10});

  final MemberStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fill = switch (status) {
      MemberStatus.online => AppColors.green,
      MemberStatus.idle => AppColors.amber,
      MemberStatus.dnd => AppColors.red,
      MemberStatus.invisible || MemberStatus.offline => null,
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: fill == null
              ? Border.all(color: AppColors.text3, width: 2)
              : null,
        ),
      ),
    );
  }
}
