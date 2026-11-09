import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/text_box.dart';
import '../widgets/app_switch.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/format_help.dart';
import '../widgets/pressable.dart';
import '../widgets/prompt.dart';
import '../widgets/scaffold.dart';
import '../widgets/tab_bar.dart';
import '../routes.dart';

/// Running a space: its name, its channels and who is in it.
///
/// The design kit has no screen for this, so it is drawn in the same
/// system. Everyone in the space can open it and see who is who. Only the
/// owner is shown the controls, and the core refuses them from anyone
/// else whatever the screen shows.
class SpaceSettingsScreen extends StatelessWidget {
  const SpaceSettingsScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    // The space can go while this is open: the user leaves, or is removed.
    if (!state.isJoined(spaceId)) {
      return const AppScreen(body: SizedBox.shrink());
    }
    final space = state.space(spaceId);
    final owner = space.role == SpaceRole.owner;
    final members = space.isBroadcast
        ? const <Person>[]
        : state.spaceMembers(spaceId);
    final roles = space.isBroadcast
        ? const <String, SpaceRole>{}
        : state.memberRoles(spaceId);
    final channels = [
      for (final group in [ChannelGroup.info, ChannelGroup.text])
        for (final channel in space.channels[group] ?? const <Channel>[])
          (channel, group == ChannelGroup.info),
    ];

    return AppScreen(
      header: AppTopBar(
        title: space.isBroadcast ? l10n.channelSettings : l10n.spaceSettings,
        subtitle: space.name,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _Label(l10n.spaceAboutSection),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (owner &&
                    state.works(Extra.spaceIcons) &&
                    state.canPickFiles)
                  _IconLine(
                    space: space,
                    onTap: () => _chooseIcon(context, space),
                  ),
                _Line(
                  icon: AppIcons.tag,
                  title: space.name,
                  detail: l10n.spaceName,
                  divider: true,
                  trailing: owner
                      ? AppIconButton(
                          icon: ExtraIcons.edit,
                          label: l10n.renameSpace,
                          color: AppColors.text2,
                          onTap: () => _rename(context, space),
                        )
                      : null,
                ),
                _Line(
                  icon: AppIcons.info,
                  title: space.description.isEmpty
                      ? l10n.noDescription
                      : plainText(space.description),
                  detail: l10n.spaceDescription,
                  divider: !space.isBroadcast,
                  trailing: owner
                      ? AppIconButton(
                          icon: ExtraIcons.edit,
                          label: l10n.editDescription,
                          color: AppColors.text2,
                          onTap: () => _describe(context, space),
                        )
                      : null,
                ),
                // A public channel has no members to welcome.
                if (!space.isBroadcast) ...[
                  _Line(
                    icon: AppIcons.megaphone,
                    title: space.welcome.isEmpty
                        ? l10n.noWelcomeYet
                        : plainText(space.welcome),
                    detail: l10n.welcomeMessage,
                    divider: true,
                    trailing: owner
                        ? AppIconButton(
                            icon: ExtraIcons.edit,
                            label: l10n.editWelcome,
                            color: AppColors.text2,
                            onTap: () => _welcome(context, space),
                          )
                        : null,
                  ),
                  _Line(
                    icon: AppIcons.lock,
                    title: space.rules.isEmpty
                        ? l10n.noRulesYet
                        : plainText(space.rules),
                    detail: l10n.spaceRules,
                    trailing: owner
                        ? AppIconButton(
                            icon: ExtraIcons.edit,
                            label: l10n.editRules,
                            color: AppColors.text2,
                            onTap: () => _rules(context, space),
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (!space.isBroadcast) ...[
            _Label(l10n.channels),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, (channel, info)) in channels.indexed)
                    _Line(
                      icon: info ? AppIcons.megaphone : AppIcons.hash,
                      title: channel.name,
                      detail: info ? l10n.channelForOwnersShort : null,
                      divider: index < channels.length - 1 || owner,
                      trailing: owner
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIconButton(
                                  icon: ExtraIcons.edit,
                                  label: l10n.renameChannelNamed(channel.name),
                                  color: AppColors.text2,
                                  onTap: () =>
                                      _renameChannel(context, space, channel),
                                ),
                                AppIconButton(
                                  icon: ExtraIcons.settings,
                                  label: l10n.channelRulesNamed(channel.name),
                                  color: AppColors.text2,
                                  onTap: () => showChannelRules(
                                    context,
                                    space.id,
                                    channel.id,
                                  ),
                                ),
                                AppIconButton(
                                  icon: ExtraIcons.trash,
                                  label: l10n.deleteChannelNamed(channel.name),
                                  color: AppColors.text2,
                                  onTap: () =>
                                      _deleteChannel(context, space, channel),
                                ),
                              ],
                            )
                          : null,
                    ),
                  if (owner)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: AppButton(
                        label: l10n.addChannel,
                        icon: AppIcons.plus,
                        height: 46,
                        onTap: () => showAddChannel(context, space.id),
                      ),
                    ),
                ],
              ),
            ),
            _Label(l10n.membersCount(members.length)),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, person) in members.indexed)
                    _MemberLine(
                      space: space,
                      person: person,
                      role: roles[person.id] ?? SpaceRole.member,
                      me: person.id == state.myId,
                      divider: index < members.length - 1,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(l10n.rolesExplained, style: AppText.footnote),
            ),
          ],
          if (owner && !space.isBroadcast) ...[
            _Label(l10n.roles),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final role in space.roleDefs)
                    Pressable(
                      onTap: () => showRoleSheet(context, space.id, role: role),
                      child: _Line(
                        icon: ExtraIcons.shield,
                        title: role.name,
                        detail: role.may.isEmpty
                            ? l10n.roleMayNothing
                            : [
                                for (final power in RolePower.values)
                                  if (role.may.contains(power))
                                    powerLabel(l10n, power),
                              ].join(', '),
                        divider: true,
                      ),
                    ),
                  Pressable(
                    onTap: () => showRoleSheet(context, space.id),
                    child: _Line(icon: AppIcons.plus, title: l10n.addRole),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(l10n.rolesBody, style: AppText.footnote),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: l10n.bannedWords,
              height: 46,
              onTap: () => _bannedWords(context, space),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                space.bannedWords.isEmpty
                    ? l10n.bannedWordsNone
                    : l10n.bannedWordsCount(space.bannedWords.length),
                style: AppText.footnote,
              ),
            ),
            if (space.bannedWords.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(l10n.wordFilterSwitch),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppSwitch(
                        value: space.wordFilterOn,
                        label: l10n.wordFilterSwitch,
                        onChanged: (on) => _tryRule(
                          context,
                          () =>
                              AppScope.read(context)
                                  .setWordFilter(space.id, on),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          // A public space's key is no secret, so there is nothing to reset.
          if (owner && !space.isPublic) ...[
            const SizedBox(height: 20),
            AppButton(
              label: l10n.resetInviteLinks,
              height: 46,
              onTap: () => _resetLinks(context, space),
            ),
          ],
          // A public channel's followers are not known to anyone, so there
          // is nobody to hand it to.
          if (owner && !space.isBroadcast) ...[
            _Label(l10n.roleOwner),
            AppCard(
              padding: EdgeInsets.zero,
              child: Pressable(
                onTap: () => _transfer(context, space),
                focusRadius: BorderRadius.circular(AppRadius.card),
                child: _Line(
                  icon: _crownIcon,
                  title: l10n.transferOwnership,
                  detail: l10n.transferOwnershipDetail,
                  trailing: const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: AppIcon(
                      AppIcons.chevronRight,
                      size: 16,
                      color: AppColors.text3,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (owner) ...[
            const SizedBox(height: 20),
            AppButton(
              label: l10n.deleteSpace,
              kind: AppButtonKind.dangerText,
              height: 46,
              onTap: () => _delete(context, space),
            ),
          ],
          if (!owner) ...[
            const SizedBox(height: 20),
            AppButton(
              label: space.isBroadcast ? l10n.stopFollowing : l10n.leaveSpace,
              kind: AppButtonKind.dangerText,
              height: 46,
              onTap: () => _leave(context, space),
            ),
          ],
        ],
      ),
    );
  }

  /// Lets the owner choose a picture or GIF for the space's icon, or take
  /// it away.
  Future<void> _chooseIcon(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              header: true,
              child: Text(
                l10n.spaceIcon,
                style: AppText.base.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              space.isPublic ? l10n.spaceIconBodyPublic : l10n.spaceIconBody,
              style: AppText.detail,
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: l10n.choosePhoto,
            icon: AppIcons.photo,
            kind: AppButtonKind.primary,
            onTap: () => Navigator.of(context).pop('choose'),
          ),
          if (space.icon != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: l10n.removeSpaceIcon,
              kind: AppButtonKind.danger,
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'remove') {
      if (!state.clearSpaceIcon(space.id)) {
        showAppRetry(
          context,
          l10n.couldNotRemoveIcon,
          () => _chooseIcon(context, space),
        );
      }
      return;
    }
    final path = await state.pickFile();
    if (path == null || !context.mounted) return;
    final done = await state.setSpaceIconFrom(space.id, path);
    if (context.mounted) {
      showAppToast(context, done ? l10n.spaceIconSet : l10n.photoNotUsable);
    }
  }

  Future<void> _rename(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showAppPrompt(
      context,
      title: l10n.renameSpace,
      label: l10n.spaceName,
      action: l10n.save,
      initial: space.name,
      check: (name) =>
          state.editSpace(space.id, name: name) ? null : l10n.nameNotUsable,
    );
  }

  Future<void> _welcome(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showWritingPrompt(
      context,
      title: l10n.welcomeMessage,
      body: l10n.welcomeMessageBody,
      label: l10n.welcomeMessage,
      action: l10n.save,
      initial: space.welcome,
      check: (text) => state.setSpaceWelcome(space.id, welcome: text)
          ? null
          : l10n.welcomeTooLong,
    );
  }

  Future<void> _rules(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showWritingPrompt(
      context,
      title: l10n.spaceRules,
      body: l10n.spaceRulesBody,
      label: l10n.spaceRules,
      action: l10n.save,
      initial: space.rules,
      check: (text) => state.setSpaceWelcome(space.id, rules: text)
          ? null
          : l10n.rulesTooLong,
    );
  }

  Future<void> _describe(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showWritingPrompt(
      context,
      title: l10n.editDescription,
      label: l10n.spaceAbout,
      action: l10n.save,
      initial: space.description,
      check: (text) => state.editSpace(space.id, description: text)
          ? null
          : l10n.descriptionTooLong,
    );
  }

  Future<void> _renameChannel(
    BuildContext context,
    Space space,
    Channel channel,
  ) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showAppPrompt(
      context,
      title: l10n.renameChannel,
      label: l10n.channelName,
      action: l10n.save,
      initial: channel.name,
      check: (name) => state.renameChannel(space.id, channel.id, name)
          ? null
          : l10n.nameNotUsable,
    );
  }

  Future<void> _deleteChannel(
    BuildContext context,
    Space space,
    Channel channel,
  ) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.deleteChannelConfirmTitle(channel.name),
      body: l10n.deleteChannelConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    if (!state.removeChannel(space.id, channel.id)) {
      showAppToast(context, l10n.lastChannelStays);
    }
  }

  Future<void> _resetLinks(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.resetInviteLinks,
      body: l10n.resetInviteLinksBody,
      confirmLabel: l10n.resetInviteLinksAction,
    );
    if (!sure || !context.mounted) return;
    if (state.resetInviteLinks(space.id)) {
      showAppToast(context, l10n.inviteLinksReset);
    } else {
      showAppRetry(
        context,
        l10n.couldNotResetLinks,
        () => _resetLinks(context, space),
      );
    }
  }

  /// Asks for the words to keep out, with commas between them.
  Future<void> _bannedWords(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showAppPrompt(
      context,
      title: l10n.bannedWords,
      body: l10n.bannedWordsBody,
      label: l10n.bannedWords,
      action: l10n.save,
      initial: space.bannedWords.join(', '),
      check: (text) => state.setBannedWords(space.id, text.split(','))
          ? null
          : l10n.bannedWordsNotUsable,
    );
  }

  /// Lets the owner choose the member to hand the space to, then says
  /// plainly what they give up before handing it over.
  Future<void> _transfer(BuildContext context, Space space) async {
    final state = AppScope.read(context);
    final roles = state.memberRoles(space.id);
    final others = [
      for (final person in state.spaceMembers(space.id))
        if (person.id != state.myId) person,
    ];
    final chosen = await showAppSheet<Person>(
      context,
      builder: (_) =>
          _TransferSheet(space: space, members: others, roles: roles),
    );
    if (chosen == null || !context.mounted) return;
    await _handOver(context, space, chosen);
  }

  Future<void> _delete(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.deleteSpaceConfirmTitle(space.name),
      body: l10n.deleteSpaceConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    if (!state.deleteSpace(space.id)) {
      showAppRetry(
        context,
        l10n.couldNotDeleteSpace,
        () => _delete(context, space),
      );
      return;
    }
    Go.home(context, AppTab.spaces);
  }

  Future<void> _leave(BuildContext context, Space space) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.leaveSpaceConfirmTitle(space.name),
      body: l10n.leaveSpaceConfirmBody(context.deviceKind),
      confirmLabel: l10n.leave,
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    if (!state.leaveSpace(space.id)) {
      showAppRetry(
        context,
        l10n.couldNotLeaveSpace,
        () => _leave(context, space),
      );
      return;
    }
    Go.home(context, AppTab.spaces);
  }
}

/// Makes one change to a space's rules, and if the core refused, says so
/// with a way to try again. Nothing here fails quietly: a switch that
/// did not take would otherwise spring back with no word of why.
void _tryRule(BuildContext context, bool Function() change) {
  if (change()) return;
  showAppRetry(
    context,
    context.l10n.couldNotSetRule,
    () => _tryRule(context, change),
  );
}

/// The same, for something done to a member, with its own words.
void _tryMember(BuildContext context, String failed, bool Function() act) {
  if (act()) return;
  showAppRetry(context, failed, () => _tryMember(context, failed, act));
}

/// The owner's rules for one channel: who writes, links, slow mode. Each
/// change is made at once, and binds what is written from then on.
Future<void> showChannelRules(
  BuildContext context,
  String spaceId,
  String channelId,
) => showAppSheet<void>(
  context,
  builder: (context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final space = state.findSpace(spaceId);
    final info = space?.channels[ChannelGroup.info] ?? const <Channel>[];
    final channel = space?.channels.values
        .expand((list) => list)
        .where((c) => c.id == channelId)
        .firstOrNull;
    if (space == null || channel == null) return const SizedBox.shrink();
    final ownersOnly = info.any((c) => c.id == channelId);

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) =>
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(child: ExcludeSemantics(child: Text(label))),
              const SizedBox(width: 12),
              AppSwitch(value: value, label: label, onChanged: onChanged),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.channelRulesNamed(channel.name),
            style: AppText.base.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(l10n.channelRulesBody, style: AppText.detail),
        const SizedBox(height: 8),
        toggle(
          l10n.channelForOwners,
          ownersOnly,
          (on) => _tryRule(
            context,
            () => state.setChannelRules(spaceId, channelId, ownersOnly: on),
          ),
        ),
        toggle(
          l10n.noLinksRule,
          channel.noLinks,
          (on) => _tryRule(
            context,
            () => state.setChannelRules(spaceId, channelId, noLinks: on),
          ),
        ),
        if (space.roleDefs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l10n.whoCanWrite, style: AppText.strong),
          Text(l10n.whoCanWriteDetail, style: AppText.detail),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: l10n.everyone,
                kind: channel.writerRoles.isEmpty
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                height: 44,
                horizontalPadding: 14,
                onTap: () => _tryRule(
                  context,
                  () => state.setChannelRules(
                    spaceId,
                    channelId,
                    writerRoles: const [],
                  ),
                ),
              ),
              for (final role in space.roleDefs)
                AppButton(
                  label: role.name,
                  kind: channel.writerRoles.contains(role.id)
                      ? AppButtonKind.primary
                      : AppButtonKind.secondary,
                  height: 44,
                  horizontalPadding: 14,
                  onTap: () => _tryRule(
                    context,
                    () => state.setChannelRules(
                      spaceId,
                      channelId,
                      writerRoles: channel.writerRoles.contains(role.id)
                          ? [
                              for (final r in channel.writerRoles)
                                if (r != role.id) r,
                            ]
                          : [...channel.writerRoles, role.id],
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(l10n.disappearRule, style: AppText.strong),
        Text(l10n.disappearRuleDetail, style: AppText.detail),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, seconds) in [
              (l10n.timerOff, 0),
              (l10n.timerHour, 3600),
              (l10n.timerDay, 86400),
              (l10n.timerWeek, 604800),
            ])
              AppButton(
                label: label,
                kind: channel.disappearSeconds == seconds
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                height: 44,
                horizontalPadding: 14,
                onTap: () => _tryRule(
                  context,
                  () => state.setChannelRules(
                    spaceId,
                    channelId,
                    disappearSeconds: seconds,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.lengthRule, style: AppText.strong),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, length) in [
              (l10n.lengthNoLimit, 0),
              (l10n.lengthChoice('200'), 200),
              (l10n.lengthChoice('500'), 500),
              (l10n.lengthChoice('2000'), 2000),
            ])
              AppButton(
                label: label,
                kind: channel.maxLength == length
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                height: 44,
                horizontalPadding: 14,
                onTap: () => _tryRule(
                  context,
                  () => state.setChannelRules(
                    spaceId,
                    channelId,
                    maxLength: length,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.slowMode, style: AppText.strong),
        Text(l10n.slowModeDetail, style: AppText.detail),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seconds in const [0, 10, 60, 300, 3600])
              AppButton(
                label: l10n.slowChoice(seconds),
                kind: channel.slowSeconds == seconds
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                height: 44,
                horizontalPadding: 14,
                onTap: () => _tryRule(
                  context,
                  () => state.setChannelRules(
                    spaceId,
                    channelId,
                    slowSeconds: seconds,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  },
);

/// Asks for a channel's name and who writes in it, and adds it.
Future<void> showAddChannel(BuildContext context, String spaceId) =>
    showAppSheet<void>(context, builder: (_) => _AddChannel(spaceId));

class _AddChannel extends StatefulWidget {
  const _AddChannel(this.spaceId);

  final String spaceId;

  @override
  State<_AddChannel> createState() => _AddChannelState();
}

class _AddChannelState extends State<_AddChannel> {
  final _name = TextEditingController();
  bool _info = false;
  bool _voice = false;
  bool _problem = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add() {
    final made = AppScope.read(context).addChannel(
      widget.spaceId,
      _name.text,
      info: _info && !_voice,
      voice: _voice,
    );
    if (made == null) {
      setState(() => _problem = true);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.addChannel,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppTextBox(
          controller: _name,
          label: l10n.channelName,
          hint: l10n.channelName,
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(child: Text(l10n.channelForOwners)),
                ),
                const SizedBox(width: 12),
                AppSwitch(
                  value: _info && !_voice,
                  label: l10n.channelForOwners,
                  onChanged: _voice ? null : (on) => setState(() => _info = on),
                ),
              ],
            ),
          ),
        ),
        // A room to talk in, where this device can carry a call.
        if (AppScope.of(context).works(Extra.voiceRooms))
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(child: Text(l10n.voiceRoomKind)),
                  ),
                  const SizedBox(width: 12),
                  AppSwitch(
                    value: _voice,
                    label: l10n.voiceRoomKind,
                    onChanged: (on) => setState(() => _voice = on),
                  ),
                ],
              ),
            ),
          ),
        if (_problem) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.nameNotUsable,
              style: AppText.base.copyWith(color: AppColors.red),
            ),
          ),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: l10n.addChannel,
          kind: AppButtonKind.primary,
          onTap: _add,
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Semantics(
        header: true,
        child: Text(text, style: AppText.sectionLabel),
      ),
    );
  }
}

/// The space's icon, or its initials, and a way for the owner to change it.
class _IconLine extends StatelessWidget {
  const _IconLine({required this.space, required this.onTap});

  final Space space;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DividedRow(
      minHeight: 64,
      divider: true,
      padding: const EdgeInsets.only(left: 14, right: 4),
      child: Row(
        children: [
          Avatar(
            tone: space.tone,
            label: space.initials,
            photo: space.icon,
            icon: space.isBroadcast && space.icon == null
                ? AppIcons.megaphone
                : null,
            size: 40,
            square: true,
            surround: AppColors.surface,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.spaceIcon),
                Text(
                  space.icon == null
                      ? l10n.spaceIconNone
                      : l10n.spaceIconChosen,
                  style: AppText.detail,
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: ExtraIcons.edit,
            label: l10n.changeSpaceIcon,
            color: AppColors.text2,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.title,
    this.detail,
    this.trailing,
    this.divider = false,
  });

  final AppIconData icon;
  final String title;
  final String? detail;
  final Widget? trailing;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return DividedRow(
      minHeight: 56,
      divider: divider,
      padding: const EdgeInsets.only(left: 14, right: 4),
      child: Row(
        children: [
          AppIcon(icon, size: 20, color: AppColors.text2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (detail != null) Text(detail!, style: AppText.detail),
              ],
            ),
          ),
          trailing ?? const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class _MemberLine extends StatelessWidget {
  const _MemberLine({
    required this.space,
    required this.person,
    required this.role,
    required this.me,
    required this.divider,
  });

  final Space space;
  final Person person;
  final SpaceRole role;
  final bool me;
  final bool divider;

  Future<void> _manage(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final admin = role == SpaceRole.admin;
    final held = state.memberRoleIds(space.id)[person.id] ?? const [];
    final choice = await showAppSheet<_MemberAction>(
      context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              header: true,
              child: Text(
                person.name,
                style: AppText.base.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: l10n.changeNickname,
            icon: AppIcons.tag,
            onTap: () => Navigator.of(sheet).pop(_MemberAction.nickname),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: admin ? l10n.removeAdmin : l10n.makeAdmin,
            icon: ExtraIcons.shield,
            onTap: () =>
                Navigator.of(sheet)
                    .pop(admin ? _MemberAction.demote : _MemberAction.promote),
          ),
          for (final role in space.roleDefs) ...[
            const SizedBox(height: 10),
            AppButton(
              label: held.contains(role.id)
                  ? l10n.takeRole(role.name)
                  : l10n.giveRole(role.name),
              height: 46,
              onTap: () {
                final on = !held.contains(role.id);
                _tryMember(
                  context,
                  l10n.couldNotGiveRole(person.name),
                  () => state.grantRole(space.id, person.id, role.id, on: on),
                );
                Navigator.of(sheet).pop();
              },
            ),
          ],
          for (final (label, action) in [
            (l10n.timeOutTen, _MemberAction.quietTen),
            (l10n.timeOutHour, _MemberAction.quietHour),
            (l10n.timeOutDay, _MemberAction.quietDay),
            (l10n.endTimeOut, _MemberAction.speak),
          ]) ...[
            const SizedBox(height: 10),
            AppButton(
              label: label,
              height: 46,
              onTap: () => Navigator.of(sheet).pop(action),
            ),
          ],
          const SizedBox(height: 10),
          AppButton(
            label: l10n.makeOwner,
            height: 46,
            onTap: () => Navigator.of(sheet).pop(_MemberAction.handOver),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: l10n.removeFromSpace,
            kind: AppButtonKind.dangerText,
            onTap: () => Navigator.of(sheet).pop(_MemberAction.remove),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case _MemberAction.nickname:
        await _nickname(context);
      case _MemberAction.promote:
        _tryMember(
          context,
          l10n.couldNotChangeAdmin(person.name),
          () => state.setAdmin(space.id, person.id, admin: true),
        );
      case _MemberAction.demote:
        _tryMember(
          context,
          l10n.couldNotChangeAdmin(person.name),
          () => state.setAdmin(space.id, person.id, admin: false),
        );
      case _MemberAction.quietTen:
        _tryMember(
          context,
          l10n.couldNotTimeOut(person.name),
          () => state.timeOutMember(space.id, person.id, 10 * 60),
        );
      case _MemberAction.quietHour:
        _tryMember(
          context,
          l10n.couldNotTimeOut(person.name),
          () => state.timeOutMember(space.id, person.id, 60 * 60),
        );
      case _MemberAction.quietDay:
        _tryMember(
          context,
          l10n.couldNotTimeOut(person.name),
          () => state.timeOutMember(space.id, person.id, 24 * 60 * 60),
        );
      case _MemberAction.speak:
        _tryMember(
          context,
          l10n.couldNotTimeOut(person.name),
          () => state.timeOutMember(space.id, person.id, 0),
        );
      case _MemberAction.handOver:
        await _handOver(context, space, person);
      case _MemberAction.remove:
        final sure = await showAppConfirm(
          context,
          title: l10n.removeMemberConfirmTitle(person.name),
          // Say only what is true. A private space changes its key, so
          // they get nothing more. A public one cannot keep anyone out.
          body: space.isPublic
              ? l10n.removeMemberConfirmBodyPublic
              : l10n.removeMemberConfirmBodyPrivate,
          confirmLabel: l10n.remove,
          destructive: true,
        );
        if (sure && context.mounted) {
          _tryMember(
            context,
            l10n.couldNotRemoveMember(person.name),
            () => state.removeFromSpace(space.id, person.id),
          );
        }
    }
  }

  /// Sets what this member is called in the space, for everyone.
  Future<void> _nickname(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    await showAppPrompt(
      context,
      title: l10n.changeNicknameOf(person.name),
      body: l10n.changeNicknameBody,
      label: l10n.nickname,
      action: l10n.save,
      initial: person.name,
      check: (name) => state.setMemberNickname(space.id, person.id, name)
          ? null
          : l10n.nameNotUsable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final owner = space.role == SpaceRole.owner;
    final admin = space.role == SpaceRole.admin;
    final held =
        AppScope.of(context).memberRoleIds(space.id)[person.id] ?? const [];
    final roleNames = [
      for (final r in space.roleDefs)
        if (held.contains(r.id)) r.name,
    ];
    return DividedRow(
      minHeight: 60,
      divider: divider,
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          Avatar(
            tone: person.tone,
            photo: person.photo,
            label: person.initial,
            size: 40,
            surround: AppColors.surface,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              me ? l10n.nameAndYou(person.name) : person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.strong,
            ),
          ),
          for (final name in roleNames) ...[
            const SizedBox(width: 6),
            AppChip(name, tone: ChipTone.neutral),
          ],
          if (role != SpaceRole.member) ...[
            const SizedBox(width: 8),
            AppChip(
              role == SpaceRole.owner ? l10n.roleOwner : l10n.roleAdmin,
              tone: role == SpaceRole.owner
                  ? ChipTone.accent
                  : ChipTone.neutral,
            ),
          ],
          // The owner manages everyone but themselves.
          if (owner && !me)
            AppIconButton(
              icon: AppIcons.more,
              label: l10n.manageMember(person.name),
              color: AppColors.text2,
              onTap: () => _manage(context),
            )
          // An admin renames members, but not the owner or another admin.
          else if (admin && !me && role == SpaceRole.member)
            AppIconButton(
              icon: AppIcons.tag,
              label: l10n.changeNicknameOf(person.name),
              color: AppColors.text2,
              onTap: () => _nickname(context),
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}

/// Handing the space to someone else.
const _crownIcon = AppIconData([
  IconPath('M3 8l4.5 3.5L12 5l4.5 6.5L21 8l-2 10H5L3 8Z'),
]);

/// Asks the owner, saying what they give up and that only the new owner
/// can give it back, then makes [person] the owner. The settings redraw
/// for the owner's new role at once, and for [person] as soon as the
/// change reaches them.
Future<void> _handOver(BuildContext context, Space space, Person person) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final sure = await showAppConfirm(
    context,
    title: l10n.handOverConfirmTitle(person.name),
    body: l10n.transferConfirmBody(person.name, space.name),
    confirmLabel: l10n.transfer,
    destructive: true,
  );
  if (!sure || !context.mounted) return;
  final done = state.handOverSpace(space.id, person.id);
  showAppToast(
    context,
    done
        ? l10n.transferDone(person.name, space.name)
        : l10n.transferFailed(person.name),
  );
}

/// The members the owner can hand the space to. Gives back the one
/// chosen.
class _TransferSheet extends StatelessWidget {
  const _TransferSheet({
    required this.space,
    required this.members,
    required this.roles,
  });

  final Space space;
  final List<Person> members;
  final Map<String, SpaceRole> roles;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const radius = BorderRadius.all(Radius.circular(AppRadius.card));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.transferOwnership,
              style: AppText.base.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            members.isEmpty
                ? l10n.transferOwnershipNobody
                : l10n.transferOwnershipBody(space.name),
            style: AppText.detail,
          ),
        ),
        if (members.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppCard(
            padding: EdgeInsets.zero,
            color: AppColors.raised,
            child: Column(
              children: [
                for (final (index, person) in members.indexed)
                  Pressable(
                    onTap: () => Navigator.of(context).pop(person),
                    focusRadius: radius,
                    child: DividedRow(
                      minHeight: 60,
                      divider: index < members.length - 1,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Avatar(
                            tone: person.tone,
                            photo: person.photo,
                            label: person.initial,
                            size: 40,
                            surround: AppColors.raised,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.strong,
                            ),
                          ),
                          if (roles[person.id] == SpaceRole.admin) ...[
                            const SizedBox(width: 8),
                            AppChip(l10n.roleAdmin, tone: ChipTone.neutral),
                          ],
                          const SizedBox(width: 8),
                          const AppIcon(
                            AppIcons.chevronRight,
                            size: 16,
                            color: AppColors.text3,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

enum _MemberAction {
  nickname,
  promote,
  demote,
  quietTen,
  quietHour,
  quietDay,
  speak,
  handOver,
  remove,
}

/// What a role's power is called on screen.
String powerLabel(AppLocalizations l10n, RolePower power) => switch (power) {
  RolePower.pin => l10n.rolePowerPin,
  RolePower.announce => l10n.rolePowerAnnounce,
  RolePower.delete => l10n.rolePowerDelete,
  RolePower.timeout => l10n.rolePowerTimeout,
  RolePower.mentionEveryone => l10n.rolePowerMentionEveryone,
};

/// Makes a role, or with [role] changes or deletes one.
Future<void> showRoleSheet(
  BuildContext context,
  String spaceId, {
  SpaceRoleDef? role,
}) => showAppSheet<void>(
  context,
  builder: (_) => _RoleSheet(spaceId: spaceId, role: role),
);

class _RoleSheet extends StatefulWidget {
  const _RoleSheet({required this.spaceId, this.role});

  final String spaceId;
  final SpaceRoleDef? role;

  @override
  State<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends State<_RoleSheet> {
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late final Set<RolePower> _may = {...?widget.role?.may};
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final role = widget.role;
    final done = role == null
        ? state.addRole(widget.spaceId, _name.text, _may) != null
        : state.editRole(widget.spaceId, role.id, name: _name.text, may: _may);
    if (done) {
      Navigator.of(context).pop();
    } else {
      setState(() => _problem = l10n.roleNotUsable);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final role = widget.role!;
    final sure = await showAppConfirm(
      context,
      title: l10n.deleteRoleConfirmTitle(role.name),
      body: l10n.deleteRoleConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!sure || !mounted) return;
    if (!state.removeRole(widget.spaceId, role.id)) {
      showAppRetry(context, l10n.couldNotRemoveRole(role.name), _delete);
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.role == null ? l10n.addRole : widget.role!.name,
            style: AppText.base.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppTextBox(
          controller: _name,
          label: l10n.roleName,
          hint: l10n.roleName,
        ),
        if (_problem != null) ...[
          const SizedBox(height: 6),
          Text(_problem!, style: AppText.detail.copyWith(color: AppColors.red)),
        ],
        const SizedBox(height: 10),
        for (final power in RolePower.values)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(child: Text(powerLabel(l10n, power))),
                ),
                const SizedBox(width: 12),
                AppSwitch(
                  value: _may.contains(power),
                  label: powerLabel(l10n, power),
                  onChanged: (on) =>
                      setState(() => on ? _may.add(power) : _may.remove(power)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        AppButton(label: l10n.save, kind: AppButtonKind.primary, onTap: _save),
        if (widget.role != null) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.deleteRole,
            kind: AppButtonKind.dangerText,
            height: 46,
            onTap: _delete,
          ),
        ],
      ],
    );
  }
}
