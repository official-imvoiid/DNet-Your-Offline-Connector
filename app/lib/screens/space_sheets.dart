import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/emoji.dart';
import '../data/models.dart';
import '../data/names.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/away_mark.dart';
import '../widgets/feedback.dart';
import '../widgets/link_text.dart';
import '../widgets/person_card.dart';
import '../widgets/pressable.dart';
import '../widgets/prompt.dart';
import '../widgets/tab_bar.dart';
import '../widgets/text_box.dart';

// The sheets that go with spaces. The design kit shows the buttons that
// open them but not the sheets themselves, so these are drawn in the same
// system: surface colour, 28 px top radius, the kit's buttons and rows.

Widget _title(String text) => Padding(
  padding: const EdgeInsets.only(left: 4),
  child: Semantics(
    header: true,
    child: Text(
      text,
      style: AppText.base.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
    ),
  ),
);

/// Asks for a name and a kind, and makes the space.
Future<void> showCreateSpace(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const _CreateSpace());

class _CreateSpace extends StatefulWidget {
  const _CreateSpace();

  @override
  State<_CreateSpace> createState() => _CreateSpaceState();
}

class _CreateSpaceState extends State<_CreateSpace> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  // Private is the default, as the choice that shares least.
  var _kind = SpaceKind.private;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  void _create() {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    // The core keeps a description to 140 characters, as it counts them.
    if (_about.text.trim().runes.length > 140) {
      showAppToast(context, l10n.descriptionTooLong);
      return;
    }
    final id = state.createSpace(
      _name.text,
      _kind,
      // A private space's description reaches its members only: a private
      // space is never announced to anyone nearby.
      description: _about.text,
    );
    if (id == null) {
      showAppToast(context, l10n.spaceNeedsName);
      return;
    }
    final navigator = Navigator.of(context);
    Go.home(context, AppTab.spaces);
    if (_kind == SpaceKind.channel) Go.publicChannel(navigator.context, id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kinds = [
      (
        SpaceKind.private,
        AppIcons.lock,
        l10n.kindPrivate,
        l10n.kindPrivateDetail,
      ),
      (
        SpaceKind.public,
        AppIcons.people,
        l10n.kindPublic,
        l10n.kindPublicDetail,
      ),
      (
        SpaceKind.channel,
        AppIcons.megaphone,
        l10n.kindChannel,
        l10n.kindChannelDetail,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(l10n.createSpace),
        const SizedBox(height: 14),
        AppTextBox(
          controller: _name,
          label: l10n.spaceName,
          hint: l10n.spaceName,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 12),
        for (final (kind, icon, title, detail) in kinds) ...[
          _Choice(
            icon: icon,
            title: title,
            detail: detail,
            selected: _kind == kind,
            onTap: () => setState(() => _kind = kind),
          ),
          const SizedBox(height: 8),
        ],
        AppTextBox(
          controller: _about,
          label: l10n.spaceAbout,
          hint: l10n.spaceAbout,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 6),
        AppButton(
          label: l10n.create,
          kind: AppButtonKind.primary,
          onTap: _create,
        ),
      ],
    );
  }
}

/// One of a few choices, of which exactly one is picked.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.largeButton);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $detail',
      selected: selected,
      focusRadius: radius,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.raised,
          borderRadius: radius,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.raised,
          ),
        ),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 22,
              color: selected ? AppColors.accent : AppColors.text2,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppText.strong),
                  Text(detail, style: AppText.detail),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 10),
              const AppIcon(AppIcons.check, size: 18, color: AppColors.accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// Invites people to a space: by a link to pass on, or a contact directly.
/// Leaving the space is here too, as the one other thing to do with it.
Future<void> showSpaceInvite(BuildContext context, Space space) =>
    showAppSheet<void>(context, builder: (_) => _Invite(space: space));

class _Invite extends StatefulWidget {
  const _Invite({required this.space});

  final Space space;

  @override
  State<_Invite> createState() => _InviteState();
}

class _InviteState extends State<_Invite> {
  final _invited = <String>{};

  /// How long a copied link lets people in. Null: for good.
  Duration? _lasts;

  Future<void> _copyLink() async {
    final l10n = context.l10n;
    final link = AppScope.read(context)
        .spaceInviteLink(widget.space.id, lasts: _lasts);
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) showAppToast(context, l10n.inviteLinkCopied);
  }

  Future<void> _leave() async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.leaveSpaceConfirmTitle(widget.space.name),
      body: l10n.leaveSpaceConfirmBody(context.deviceKind),
      confirmLabel: l10n.leave,
      destructive: true,
    );
    if (!sure || !mounted) return;
    if (!state.leaveSpace(widget.space.id)) {
      showAppRetry(context, l10n.couldNotLeaveSpace, _leave);
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final space = widget.space;
    final members = {for (final m in state.spaceMembers(space.id)) m.id};
    final contacts = [
      for (final person in state.contacts)
        if (!members.contains(person.id)) person,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(l10n.inviteToSpace(space.name)),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(l10n.linkLasts, style: AppText.sectionLabel),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, lasts) in [
              (l10n.linkLastsForGood, null),
              (l10n.linkLastsHour, const Duration(hours: 1)),
              (l10n.linkLastsDay, const Duration(days: 1)),
              (l10n.linkLastsWeek, const Duration(days: 7)),
            ])
              AppButton(
                label: label,
                kind: _lasts == lasts
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                height: 44,
                horizontalPadding: 14,
                onTap: () => setState(() => _lasts = lasts),
              ),
          ],
        ),
        if (_lasts != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l10n.linkRunsOutNote, style: AppText.detail),
          ),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: l10n.copyInviteLink,
          icon: AppIcons.link,
          kind: AppButtonKind.primary,
          onTap: _copyLink,
        ),
        // A public channel keeps no list of followers, so there is nobody
        // to invite into it by name: its link is the whole invitation.
        if (!space.isBroadcast) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l10n.yourContacts, style: AppText.sectionLabel),
          ),
          const SizedBox(height: 6),
          if (contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Text(
                l10n.noContactsToInvite,
                style: AppText.base.copyWith(color: AppColors.text2),
              ),
            ),
          for (final person in contacts)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Avatar(
                      tone: person.tone,
                      photo: person.photo,
                      label: person.initial,
                      size: 44,
                      surround: AppColors.surface,
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
                    const SizedBox(width: 12),
                    AppButton(
                      label: _invited.contains(person.id)
                          ? l10n.invited
                          : l10n.invite,
                      height: 44,
                      horizontalPadding: 14,
                      onTap: _invited.contains(person.id)
                          ? null
                          : () {
                              if (state.inviteToSpace(space.id, person.id)) {
                                setState(() => _invited.add(person.id));
                              }
                            },
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 10),
        AppButton(
          label: l10n.leaveSpace,
          kind: AppButtonKind.dangerText,
          height: 46,
          onTap: _leave,
        ),
      ],
    );
  }
}

/// Lists who is in a space.
Future<void> showSpaceMembers(BuildContext context, Space space) =>
    showAppSheet<void>(
      context,
      builder: (context) => SpaceMemberList(space: space),
    );

/// The members of [space], each with their picture, their name and how
/// they say they are. Tapping someone else shows who they are. Used in a
/// sheet, and beside a channel on a big window.
class SpaceMemberList extends StatelessWidget {
  const SpaceMemberList({
    super.key,
    required this.space,
    this.surround = AppColors.surface,
  });

  final Space space;

  /// The colour behind the list, which the pictures' rings match.
  final Color surround;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final members = state.spaceMembers(space.id);
    // How each says they are, where that is built. A public channel
    // lists nobody, so has nobody to show.
    final statuses = state.works(Extra.memberStatus) && !space.isBroadcast
        ? state.memberStatuses(space.id)
        : const <String, MemberStatus>{};
    // Two members with one name are told apart by their tags.
    final shared = Names.shared([
      for (final person in members) (key: person.id, name: person.name),
    ]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(l10n.membersCount(members.length)),
        const SizedBox(height: 10),
        for (final person in members)
          Pressable(
            onTap: person.id == state.myId
                ? null
                : () => showPersonCard(context, person.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Avatar(
                      tone: person.tone,
                      photo: person.photo,
                      label: person.initial,
                      size: 40,
                      surround: surround,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        Names.shown(person.name, person.id, shared),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.strong,
                      ),
                    ),
                    if ((person.id == state.myId
                            ? state.myAway
                            : state.person(person.id).away)
                        case final away?) ...[
                      const SizedBox(width: 6),
                      AwayMark(note: away),
                    ],
                    const Spacer(),
                    if (statuses[person.id] case final status?) ...[
                      const SizedBox(width: 12),
                      StatusDot(status),
                      const SizedBox(width: 6),
                      Text(statusName(l10n, status), style: AppText.detail),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Passes [text] on, to a text channel the user may write in or to a
/// contact. It goes as the user's own message, marked as passed on, and
/// says nothing of where it came from or who wrote it first. The channel
/// or chat it came from is left off the list.
Future<void> showForwardSheet(
  BuildContext context, {
  required String text,
  String? fromChannel,
  String? fromChat,
}) async {
  final l10n = context.l10n;
  final state = AppScope.read(context);
  final channels = state.forwardTargets(exceptChannel: fromChannel);
  final contacts = [
    for (final person in state.contacts)
      if (person.id != fromChat) person,
  ];
  Widget section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
    child: Semantics(header: true, child: Text(label, style: AppText.footnote)),
  );
  final chosen = await showAppSheet<({String? channel, String? chat})>(
    context,
    builder: (context) {
      void choose({String? channel, String? chat}) =>
          Navigator.of(context).pop((channel: channel, chat: chat));
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(l10n.forwardTitle),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              channels.isEmpty && contacts.isEmpty
                  ? l10n.nowhereToForward
                  : l10n.forwardBody,
              style: AppText.detail,
            ),
          ),
          if (channels.isNotEmpty) section(l10n.forwardChannels),
          for (final (space, channel) in channels)
            Pressable(
              onTap: () => choose(channel: channel.id),
              semanticLabel: l10n.forwardToChannel(channel.name, space.name),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      AppIcon(
                        channel.kind == ChannelKind.announcements
                            ? AppIcons.megaphone
                            : AppIcons.hash,
                        size: 18,
                        color: AppColors.text2,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.strong,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          space.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.detail,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (contacts.isNotEmpty) section(l10n.forwardContacts),
          for (final person in contacts)
            Pressable(
              onTap: () => choose(chat: person.id),
              semanticLabel: l10n.forwardToContact(person.name),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Avatar(
                        tone: person.tone,
                        photo: person.photo,
                        label: person.initial,
                        size: 32,
                        surround: AppColors.surface,
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
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  if (chosen == null || !context.mounted) return;
  if (chosen.channel case final channel?) {
    final refused = state.forwardToChannel(channel, text);
    showAppToast(
      context,
      refused == null ? l10n.forwarded : refusalText(l10n, refused),
    );
  } else if (chosen.chat case final chat?) {
    showAppToast(
      context,
      state.forwardToChat(chat, text) ? l10n.forwarded : l10n.forwardFailed,
    );
  }
}

/// The space's rules as the owner wrote them, with the welcome above.
Future<void> showSpaceRules(BuildContext context, Space space) =>
    showAppSheet<void>(
      context,
      builder: (context) {
        final l10n = context.l10n;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(l10n.spaceRulesOf(space.name)),
            if (space.welcome.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LinkText(space.welcome, style: AppText.detail),
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: space.rules.isEmpty
                  ? Text(l10n.noRulesYet, style: AppText.detail)
                  : LinkText(space.rules, style: AppText.base),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(l10n.rulesSignedNote, style: AppText.footnote),
            ),
          ],
        );
      },
    );

/// What can be done with a message in a channel.
enum MessageAction { heart, agree, reply, forward, edit, pin, unpin, delete }

/// Offers what can be done with a message: the two reactions, a reply
/// where the user may write, and pinning for the space's owner.
///
/// With [onEmoji], any emoji can be given too: a few at hand, and the rest
/// from the emoji picker. With [onKeepSticker], a sticker of someone's own
/// can be kept. Either is called once the sheet has closed.
Future<MessageAction?> showMessageActions(
  BuildContext context, {
  required bool canReply,
  required bool canPin,
  required bool pinned,
  bool canDelete = false,
  bool canEdit = false,
  bool canForward = false,
  ValueChanged<String>? onEmoji,
  VoidCallback? onKeepSticker,
}) => showAppSheet<MessageAction>(
  context,
  builder: (sheet) {
    final l10n = sheet.l10n;
    void choose(MessageAction action) => Navigator.of(sheet).pop(action);
    void then(VoidCallback done) {
      Navigator.of(sheet).pop();
      done();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(l10n.react),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: l10n.reactHeart,
                icon: AppIcons.heart,
                onTap: () => choose(MessageAction.heart),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: l10n.reactAgree,
                icon: AppIcons.check,
                onTap: () => choose(MessageAction.agree),
              ),
            ),
          ],
        ),
        if (onEmoji != null) ...[
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final emoji in quickReactions)
                EmojiButton(
                  emoji: emoji,
                  label: l10n.reactWithEmoji(emoji),
                  onTap: () => then(() => onEmoji(emoji)),
                ),
              Pressable(
                onTap: () => then(() async {
                  final chosen = await showEmojiPicker(context);
                  if (chosen != null) onEmoji(chosen);
                }),
                semanticLabel: l10n.moreEmoji,
                child: const SizedBox(
                  width: kMinTouchTarget,
                  height: kMinTouchTarget,
                  child: Center(
                    child: AppIcon(
                      AppIcons.plus,
                      size: 22,
                      color: AppColors.text2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        if (onKeepSticker != null) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.saveAsSticker,
            icon: ExtraIcons.sticker,
            onTap: () => then(onKeepSticker),
          ),
        ],
        if (canReply) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.reply,
            icon: AppIcons.reply,
            onTap: () => choose(MessageAction.reply),
          ),
        ],
        if (canForward) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.forwardMessage,
            icon: ExtraIcons.send,
            onTap: () => choose(MessageAction.forward),
          ),
        ],
        if (canEdit) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.editMessage,
            icon: ExtraIcons.edit,
            onTap: () => choose(MessageAction.edit),
          ),
        ],
        if (canPin) ...[
          const SizedBox(height: 10),
          AppButton(
            label: pinned ? l10n.unpinMessage : l10n.pinMessage,
            icon: AppIcons.pin,
            onTap: () =>
                choose(pinned ? MessageAction.unpin : MessageAction.pin),
          ),
        ],
        if (canDelete) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.deleteMessage,
            icon: ExtraIcons.trash,
            kind: AppButtonKind.dangerText,
            onTap: () => choose(MessageAction.delete),
          ),
        ],
      ],
    );
  },
);

/// What the "more" button of a space offers.
enum SpaceMenuChoice { members, rules, invite, settings, mute, copyLink }

/// The "more" menu of a space or public channel. Returns what was chosen.
Future<SpaceMenuChoice?> showSpaceMenu(
  BuildContext context, {
  required Space space,
  required bool muted,
  required bool canManage,
}) => showAppSheet<SpaceMenuChoice>(
  context,
  builder: (context) {
    final l10n = context.l10n;
    Widget item(String label, AppIconData icon, SpaceMenuChoice choice) =>
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppButton(
            label: label,
            icon: icon,
            onTap: () => Navigator.of(context).pop(choice),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(space.name),
        const SizedBox(height: 4),
        if (!space.isBroadcast) ...[
          item(l10n.members, AppIcons.people, SpaceMenuChoice.members),
          item(l10n.spaceRules, AppIcons.info, SpaceMenuChoice.rules),
          item(l10n.inviteSomeone, AppIcons.personAdd, SpaceMenuChoice.invite),
        ] else
          item(l10n.copyInviteLink, AppIcons.link, SpaceMenuChoice.copyLink),
        if (canManage)
          item(
            space.isBroadcast ? l10n.channelSettings : l10n.spaceSettings,
            ExtraIcons.settings,
            SpaceMenuChoice.settings,
          ),
        item(
          muted ? l10n.unmute : l10n.mute,
          AppIcons.micOff,
          SpaceMenuChoice.mute,
        ),
      ],
    );
  },
);

/// Shows the whole of a pinned message. Returns true if the owner chose to
/// take it down.
Future<bool> showPinned(
  BuildContext context, {
  required String text,
  required bool canUnpin,
}) async =>
    await showAppSheet<bool>(
      context,
      builder: (context) {
        final l10n = context.l10n;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(l10n.pinnedMessage),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(text, style: AppText.base),
            ),
            if (canUnpin) ...[
              const SizedBox(height: 16),
              AppButton(
                label: l10n.unpinMessage,
                icon: AppIcons.pin,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ],
          ],
        );
      },
    ) ??
    false;

/// Asks for a question and its choices, and posts the poll in a channel.
Future<void> showNewPoll(
  BuildContext context, {
  String? channelId,
  String? chatId,
}) => showAppSheet<void>(
  context,
  builder: (_) => _NewPoll(channelId: channelId, chatId: chatId),
);

class _NewPoll extends StatefulWidget {
  const _NewPoll({this.channelId, this.chatId});

  /// Where the poll goes: a channel, or the chat with one person.
  final String? channelId;
  final String? chatId;

  @override
  State<_NewPoll> createState() => _NewPollState();
}

class _NewPollState extends State<_NewPoll> {
  /// The core takes no more than this.
  static const _most = 6;

  final _question = TextEditingController();
  final _choices = [TextEditingController(), TextEditingController()];
  bool _problem = false;

  @override
  void dispose() {
    _question.dispose();
    for (final choice in _choices) {
      choice.dispose();
    }
    super.dispose();
  }

  void _send() {
    final state = AppScope.read(context);
    final choices = [for (final choice in _choices) choice.text];
    final sent = switch ((widget.channelId, widget.chatId)) {
      (final channel?, _) => state.sendPoll(channel, _question.text, choices),
      (_, final chat?) => state.sendDirectPoll(chat, _question.text, choices),
      _ => false,
    };
    if (sent) {
      Navigator.of(context).pop();
    } else {
      setState(() => _problem = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(l10n.newPoll),
        const SizedBox(height: 14),
        AppTextBox(
          controller: _question,
          label: l10n.pollQuestion,
          hint: l10n.pollQuestion,
        ),
        for (final (index, choice) in _choices.indexed) ...[
          const SizedBox(height: 10),
          AppTextBox(
            controller: choice,
            label: l10n.pollChoice(index + 1),
            hint: l10n.pollChoice(index + 1),
          ),
        ],
        if (_choices.length < _most) ...[
          const SizedBox(height: 10),
          AppButton(
            label: l10n.addChoice,
            icon: AppIcons.plus,
            height: 46,
            onTap: () => setState(() => _choices.add(TextEditingController())),
          ),
        ],
        if (_problem) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.pollNeedsTwo,
              style: AppText.base.copyWith(color: AppColors.red),
            ),
          ),
        ],
        const SizedBox(height: 14),
        AppButton(
          label: l10n.sendPoll,
          kind: AppButtonKind.primary,
          onTap: _send,
        ),
      ],
    );
  }
}

/// What readers have said under a post in a public channel, with a box to
/// add to it for someone who follows the channel.
Future<void> showComments(
  BuildContext context, {
  required String spaceId,
  required String postId,
}) => showAppSheet<void>(
  context,
  builder: (_) => _Comments(spaceId: spaceId, postId: postId),
);

class _Comments extends StatefulWidget {
  const _Comments({required this.spaceId, required this.postId});

  final String spaceId;
  final String postId;

  @override
  State<_Comments> createState() => _CommentsState();
}

class _CommentsState extends State<_Comments> {
  final _box = TextEditingController();

  @override
  void dispose() {
    _box.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    AppScope.read(context).sendComment(widget.spaceId, widget.postId, text);
    _box.clear();
  }

  bool _runs(AppState state) =>
      state.findSpace(widget.spaceId)?.may(RolePower.delete) ?? false;

  /// Holding one's own comment offers changing it or taking it down.
  Future<void> _mine(ChannelMessage comment) async {
    final l10n = context.l10n;
    final choice = await showAppSheet<MessageAction>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: l10n.editMessage,
            icon: ExtraIcons.edit,
            onTap: () => Navigator.of(context).pop(MessageAction.edit),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: l10n.deleteMessage,
            icon: ExtraIcons.trash,
            kind: AppButtonKind.dangerText,
            onTap: () => Navigator.of(context).pop(MessageAction.delete),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case MessageAction.edit:
        final state = AppScope.read(context);
        await showAppPrompt(
          context,
          title: l10n.editMessageTitle,
          label: l10n.editMessage,
          action: l10n.save,
          initial: comment.text ?? '',
          check: (text) {
            final done = state.editComment(widget.spaceId, comment.id, text);
            if (done.changed) return null;
            final refused = done.refused;
            return refused == null
                ? l10n.editNotDone
                : refusalText(l10n, refused);
          },
        );
      case MessageAction.delete:
        await _delete(comment);
      default:
        return;
    }
  }

  Future<void> _delete(ChannelMessage comment) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sure = await showAppConfirm(
      context,
      title: l10n.deleteMessageConfirmTitle,
      body: l10n.deleteMessageConfirmBody,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (sure) state.deletePost(widget.spaceId, comment.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final comments = state.postComments(widget.spaceId, widget.postId);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _title(l10n.comments)),
            AppIconButton(
              icon: AppIcons.close,
              label: l10n.close,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Text(
              l10n.noCommentsYet,
              style: AppText.base.copyWith(color: AppColors.text2),
            ),
          ),
        for (final comment in comments)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Its writer can take a comment down, and so can whoever runs
            // the channel.
            onLongPress: comment.authorId == meId
                ? () => _mine(comment)
                : _runs(state)
                ? () => _delete(comment)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          comment.authorId == meId
                              ? state.profileName
                              : state.person(comment.authorId).name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.strong,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(comment.time, style: AppText.timestamp),
                      if (comment.edited) ...[
                        const SizedBox(width: 6),
                        Text(l10n.messageEdited, style: AppText.timestamp),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(comment.text ?? ''),
                ],
              ),
            ),
          ),
        if (state.canComment(widget.spaceId)) ...[
          const SizedBox(height: 10),
          AppTextBox(
            controller: _box,
            label: l10n.writeComment,
            hint: l10n.writeComment,
            textInputAction: TextInputAction.send,
            onSubmitted: _send,
          ),
          const SizedBox(height: 8),
          // Following is private. Commenting is not, so say so.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(l10n.commentNameShown, style: AppText.detail),
          ),
        ],
      ],
    );
  }
}

/// Offers the two reactions for a post. Returns the one chosen.
Future<ReactionKind?> showReactions(BuildContext context) =>
    showAppSheet<ReactionKind>(
      context,
      builder: (context) {
        final l10n = context.l10n;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(l10n.react),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (kind, icon, label) in [
                  (ReactionKind.heart, AppIcons.heart, l10n.reactHeart),
                  (ReactionKind.agree, AppIcons.check, l10n.reactAgree),
                ]) ...[
                  if (kind != ReactionKind.heart) const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: label,
                      icon: icon,
                      onTap: () => Navigator.of(context).pop(kind),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );

/// Why one of a channel's rules stopped a message, in words.
String refusalText(AppLocalizations l10n, Refused refused) => refused.links
    ? l10n.linksNotAllowed
    : refused.everyoneNotAllowed
    ? l10n.everyoneNotAllowed
    : refused.banned
    ? l10n.bannedWordRefused
    : refused.roleNeeded
    ? l10n.roleNeededRefused
    : refused.maxLength > 0
    ? l10n.tooLongRefused(refused.maxLength)
    : refused.timeoutSeconds > 0
    ? l10n.timedOutWait((refused.timeoutSeconds / 60).ceil())
    : l10n.slowModeWait(refused.waitSeconds);
