import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../design/extra_icons.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/format_help.dart';
import '../widgets/link_text.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import 'space_sheets.dart';

/// 07 Space. A rail of the user's spaces on the left, and the channels of
/// the selected one on the right.
class SpaceScreen extends StatelessWidget {
  const SpaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final space = state.selectedSpace;
    return AppScreen(
      safeBottom: false,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(spaces: state.spaces, selectedId: space?.id),
          Expanded(
            child: space == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.spacesEmpty,
                            textAlign: TextAlign.center,
                            style: AppText.base.copyWith(
                              color: AppColors.text2,
                            ),
                          ),
                          const SizedBox(height: 16),
                          AppButton(
                            label: context.l10n.findOrCreateSpace,
                            kind: AppButtonKind.primary,
                            height: 48,
                            onTap: () => Go.findSpace(context),
                          ),
                        ],
                      ),
                    ),
                  )
                : _SpaceColumn(space: space),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.spaces, required this.selectedId});

  final List<Space> spaces;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      container: true,
      label: l10n.spacesNavigation,
      child: Container(
        width: 72,
        color: AppColors.surface,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              for (final space in spaces) ...[
                Pressable(
                  onTap: () => space.isBroadcast
                      ? Go.publicChannel(context, space.id)
                      : state.selectSpace(space.id),
                  semanticLabel: space.name,
                  selected: space.id == selectedId,
                  focusRadius: radius,
                  child: Avatar(
                    tone: space.tone,
                    label: space.initials,
                    photo: space.icon,
                    icon: space.isBroadcast && space.icon == null
                        ? AppIcons.megaphone
                        : null,
                    square: true,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    surround: AppColors.surface,
                    ringColor: space.id == selectedId ? AppColors.accent : null,
                    ringWidth: 2,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(width: 28, height: 1, color: AppColors.line),
              const SizedBox(height: 12),
              Pressable(
                onTap: () => Go.findSpace(context),
                semanticLabel: l10n.findOrCreateSpace,
                focusRadius: radius,
                child: const SizedBox.square(
                  dimension: 48,
                  child: CustomPaint(
                    painter: _DashedBox(),
                    child: Center(
                      child: AppIcon(
                        AppIcons.plus,
                        size: 22,
                        color: AppColors.text2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 1 px dashed rounded square, for the "find or create a space" button.
class _DashedBox extends CustomPainter {
  const _DashedBox();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.text3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(AppRadius.card - 0.5),
        ),
      );
    const dash = 3.0, gap = 3.0;
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => false;
}

class _SpaceColumn extends StatelessWidget {
  const _SpaceColumn({required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final groups = [
      for (final (group, label) in [
        (ChannelGroup.info, l10n.sectionInfo),
        (ChannelGroup.text, l10n.sectionText),
        (ChannelGroup.voice, l10n.sectionVoice),
      ])
        if (space.channels[group]?.isNotEmpty ?? false) (group, label),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        space.name,
                        style: AppText.base.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AppChip(
                          space.isPublic ? l10n.publicSpace : l10n.privateSpace,
                          icon: space.isPublic ? null : AppIcons.lock,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            l10n.membersCount(space.memberCount),
                            style: AppText.detail,
                          ),
                        ),
                      ],
                    ),
                    // What the space is about, as the owner wrote it.
                    if (space.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        plainText(space.description),
                        style: AppText.base.copyWith(color: AppColors.text2),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (AppScope.of(context).canManageSpaces)
                AppIconButton(
                  icon: ExtraIcons.settings,
                  label: l10n.spaceSettings,
                  onTap: () => Go.spaceSettings(context, space.id),
                ),
              AppIconButton(
                icon: AppIcons.personAdd,
                label: l10n.inviteSomeone,
                onTap: () => showSpaceInvite(context, space),
              ),
            ],
          ),
        ),
        Expanded(
          child: FillScroll(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              // Joined by a pasted invite, and no member met yet: only the
              // name is known.
              if (!space.ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: Text(
                    l10n.spaceWaiting,
                    style: AppText.base.copyWith(color: AppColors.text2),
                  ),
                ),
              // What the owner says to everyone who joins.
              if (space.welcome.isNotEmpty || space.rules.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const AppIcon(
                              AppIcons.megaphone,
                              size: 16,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.welcomeTo(space.name),
                                style: AppText.strong,
                              ),
                            ),
                          ],
                        ),
                        if (space.welcome.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          LinkText(space.welcome, style: AppText.detail),
                        ],
                        if (space.rules.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          AppButton(
                            label: l10n.readTheRules,
                            icon: AppIcons.info,
                            height: 44,
                            onTap: () => showSpaceRules(context, space),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              for (final (index, (group, label)) in groups.indexed) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(10, index == 0 ? 6 : 10, 10, 4),
                  child: Text(label, style: AppText.sectionLabel),
                ),
                for (final channel in space.channels[group]!) ...[
                  _ChannelRow(
                    space: space,
                    channel: channel,
                    selected: channel.id == space.openChannelId,
                  ),
                  const SizedBox(height: 2),
                  for (final id in channel.talkerIds) ...[
                    _Talker(
                      person: AppScope.of(context).person(id),
                      speaking: id == channel.speakingId,
                    ),
                    const SizedBox(height: 2),
                  ],
                ],
              ],
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                child: Row(
                  children: [
                    const AppIcon(
                      AppIcons.verified,
                      size: 14,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.spaceFootnote(context.deviceKind),
                        style: AppText.footnote,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.space,
    required this.channel,
    required this.selected,
  });

  final Space space;
  final Channel channel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = selected ? AppColors.text : AppColors.text2;
    final radius = BorderRadius.circular(AppRadius.channelRow);
    final voice = channel.kind == ChannelKind.voice;
    return Pressable(
      onTap: () {
        if (voice) {
          // Talking needs a microphone and speaker the app can use here.
          if (AppScope.read(context).works(Extra.voiceRooms)) {
            Go.voiceRoom(context, space.id, channel.id);
          } else {
            showNotBuiltYet(context);
          }
        } else {
          AppScope.read(context).openChannel(space.id, channel.id);
          Go.channel(context, space.id, channel.id);
        }
      },
      selected: selected,
      focusRadius: radius,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.selected : null,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            AppIcon(
              switch (channel.kind) {
                ChannelKind.announcements => AppIcons.megaphone,
                ChannelKind.text => AppIcons.hash,
                ChannelKind.voice => AppIcons.speaker,
              },
              size: 18,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: LinkText(
                channel.name,
                maxLines: 1,
                style: AppText.base.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (channel.mentions > 0) ...[
              MentionBadge(channel.mentions),
              const SizedBox(width: 6),
            ],
            if (channel.unread > 0) CountBadge(channel.unread),
            if (voice && channel.talkerIds.isNotEmpty)
              Text(
                l10n.talkingCount(channel.talkerIds.length),
                style: AppText.base.copyWith(
                  color: AppColors.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Someone inside a voice room, listed under it.
class _Talker extends StatelessWidget {
  const _Talker({required this.person, required this.speaking});

  final Person person;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 34),
      child: Padding(
        padding: const EdgeInsets.only(left: 38, right: 10),
        child: Row(
          children: [
            Avatar(
              tone: person.tone,
              label: person.initial,
              size: 24,
              ringColor: speaking ? AppColors.green : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                person.name,
                style: AppText.base.copyWith(
                  fontSize: 14,
                  color: speaking ? AppColors.text : AppColors.text2,
                ),
              ),
            ),
            if (speaking)
              Semantics(label: context.l10n.speaking, child: const SizedBox()),
          ],
        ),
      ),
    );
  }
}
