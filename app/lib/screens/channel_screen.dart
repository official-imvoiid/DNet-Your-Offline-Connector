import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/image_bounds.dart';
import '../data/emoji.dart';
import '../data/live_directory.dart' show LiveDirectory;
import '../data/models.dart';
import '../data/names.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../shell/shortcuts.dart';
import '../widgets/away_mark.dart';
import '../widgets/format_help.dart';
import '../widgets/link_text.dart';
import '../widgets/person_card.dart';
import '../widgets/location_card.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/composer.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/prompt.dart';
import '../widgets/reaction_pill.dart';
import '../widgets/scaffold.dart';
import '../widgets/sticker_view.dart';
import '../widgets/text_box.dart';
import '../widgets/thread.dart';
import '../widgets/video_view.dart';
import '../widgets/voice_note.dart';
import 'direct_message_screen.dart' show RecordingBar;
import 'space_sheets.dart';

/// From this width up a channel has room for its members beside it, as a
/// third pane on a big window.
const double kMemberPaneFrom = 1000;

/// How wide the members beside a channel are.
const double kMemberPaneWidth = 264;

/// 08 Channel. Group conversation inside a space. Messages are flat rows,
/// not bubbles. With room, the space's members are listed beside it.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({
    super.key,
    required this.spaceId,
    required this.channelId,
  });

  final String spaceId;
  final String channelId;

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  /// The message the next thing written will answer, if any.
  ChannelMessage? _replyingTo;

  /// Redraws once "typing" has had time to go quiet, since nothing else
  /// may happen to make the screen look again.
  Timer? _typingFade;

  /// Searching this channel: what is looked for, while the box is open.
  final _query = TextEditingController();
  bool _searching = false;

  /// Changes each time search is asked for, so the box takes the cursor
  /// again even if it was open.
  int _searchAsked = 0;

  /// The thread, so the user can be brought back down to the newest, and
  /// the line over what was new, so they can be taken up to it.
  final _scroll = ScrollController();
  final _newLine = GlobalKey(debugLabel: 'new messages');

  /// Whether the members are listed beside the channel where there is
  /// room. They are until the user hides them, for as long as the app
  /// runs.
  static bool _membersBeside = true;

  /// How many messages from others were new when the channel was opened.
  /// The "New messages" line sits above the first of them while the
  /// screen stays open.
  late final int _newWhenOpened = AppScope.read(context)
      .newWhenOpened(widget.channelId);

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typingFade?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Opens the search box, or puts the cursor back in it.
  void _openSearch() => setState(() {
    _searching = true;
    _searchAsked++;
  });

  /// Esc closes the search box, then drops the reply being written, before
  /// it leaves the channel.
  bool _escape() {
    if (_searching) {
      setState(() {
        _searching = false;
        _query.clear();
      });
      return true;
    }
    if (_replyingTo != null) {
      setState(() => _replyingTo = null);
      return true;
    }
    return false;
  }

  /// Whether [message] has [query] in its words, its poll, its file's
  /// name or its writer's name. Capitals do not matter.
  bool _matches(AppState state, ChannelMessage message, String query) {
    final author = message.authorId == meId
        ? state.profileName
        : state.person(message.authorId).name;
    return [
      message.text,
      message.poll?.question,
      ...?message.poll?.options.map((o) => o.label),
      message.file?.name,
      author,
    ].any((part) => part != null && part.toLowerCase().contains(query));
  }

  /// The message the "New messages" line goes above: the oldest of the
  /// last [_newWhenOpened] written by others. Null if there were none.
  String? _firstNew(List<ChannelMessage> messages) {
    var left = _newWhenOpened;
    if (left <= 0) return null;
    for (final message in messages.reversed) {
      if (message.authorId == meId) continue;
      left--;
      if (left == 0) return message.id;
    }
    return messages.isEmpty ? null : messages.first.id;
  }

  /// Who is writing here right now, as a line to show, or null.
  String? _typingLine(AppLocalizations l10n, AppState state) {
    final names = [
      for (final id in state.typingInChannelNow(widget.channelId))
        state.person(id).name,
    ];
    if (names.isEmpty) return null;
    _typingFade ??= Timer(
      LiveDirectory.typingFor + const Duration(milliseconds: 200),
      () {
        _typingFade = null;
        if (mounted) setState(() {});
      },
    );
    return switch (names) {
      [final one] => l10n.typingOne(one),
      [final first, final second] => l10n.typingTwo(first, second),
      _ => l10n.typingMany,
    };
  }

  /// Shows the whole pinned message, and lets the owner take it down.
  Future<void> _openPinned(String text, {required bool canUnpin}) async {
    final state = AppScope.read(context);
    final unpin = await showPinned(context, text: text, canUnpin: canUnpin);
    final pinned = state.pinnedMessageId(widget.channelId);
    if (unpin && pinned != null) {
      state.setPinned(widget.channelId, pinned, on: false);
    }
  }

  /// The "more" button: what else can be done with this space.
  Future<void> _menu(Space space) async {
    final state = AppScope.read(context);
    final choice = await showSpaceMenu(
      context,
      space: space,
      muted: state.isMuted(space.id),
      canManage: state.canManageSpaces,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case SpaceMenuChoice.members:
        showSpaceMembers(context, space);
      case SpaceMenuChoice.rules:
        showSpaceRules(context, space);
      case SpaceMenuChoice.invite:
        showSpaceInvite(context, space);
      case SpaceMenuChoice.settings:
        Go.spaceSettings(context, space.id);
      case SpaceMenuChoice.mute:
        state.toggleMuted(space.id);
      case SpaceMenuChoice.copyLink:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    // The space can go while this screen is open, if the user leaves it.
    if (!state.isJoined(widget.spaceId)) {
      return const AppScreen(body: SizedBox.shrink());
    }
    return Actions(
      actions: {
        SearchIntent: CallbackAction<SearchIntent>(
          onInvoke: (_) {
            _openSearch();
            return null;
          },
        ),
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxWidth >= kMemberPaneFrom;
          final beside = roomy && _membersBeside;
          return Row(
            children: [
              Expanded(child: _channel(context, state, roomy: roomy)),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  child: beside
                      ? _MemberPane(space: state.space(widget.spaceId))
                      : const SizedBox(height: double.infinity),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The channel itself. [roomy] says whether its members can be listed
  /// beside it, and so whether the members button shows and hides them
  /// there or opens them in a sheet.
  Widget _channel(BuildContext context, AppState state, {required bool roomy}) {
    final l10n = context.l10n;
    final spaceId = widget.spaceId;
    final channelId = widget.channelId;
    final space = state.space(spaceId);
    final channel = state.channel(spaceId, channelId);
    final all = state.channelMessages(channelId);
    final query = _searching ? _query.text.trim().toLowerCase() : '';
    final messages = query.isEmpty
        ? all
        : [
            for (final message in all)
              if (_matches(state, message, query)) message,
          ];
    final firstNew = query.isEmpty ? _firstNew(all) : null;
    final pinned = state.pinnedMessage(channelId);
    // Only a space's owner writes in its Info channels.
    final ownersOnly =
        space.channels[ChannelGroup.info]?.any((c) => c.id == channelId) ??
        false;
    // A role may let a member write in the Info channels; a channel may be
    // kept for some roles to write in.
    final canWrite =
        (!ownersOnly || space.may(RolePower.announce)) && channel.canWrite;
    final keptFor = [
      for (final role in space.roleDefs)
        if (channel.writerRoles.contains(role.id)) role.name,
    ];
    final replyingTo = _replyingTo;
    final typing = _typingLine(l10n, state);
    final members = state.spaceMembers(spaceId);
    // Names two members share are told apart by a tag from the key.
    final shared = Names.shared([
      for (final person in members)
        if (person.id != state.myId) (key: person.id, name: person.name),
    ], mine: state.profileName);
    final List<MentionTarget> people = [
      for (final person in members) (key: person.id, name: person.name),
    ];

    /// The notes for whoever [text] calls on that said they are away.
    List<String> awayNotes(String text) {
      final lower = text.toLowerCase();
      return [
        for (final person in members)
          if (person.id != state.myId && state.person(person.id).away != null)
            if (_callsOn(lower, person.name, person.id, shared))
              awayNote(l10n, person.name, state.person(person.id).away!),
      ];
    }

    return AppScreen(
      onEscape: _escape,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTopBar(
            titleIcon: channel.kind == ChannelKind.announcements
                ? AppIcons.megaphone
                : AppIcons.hash,
            title: plainText(channel.name),
            subtitle: l10n.channelSubtitle(space.name, space.nearbyCount),
            actions: [
              AppIconButton(
                icon: AppIcons.search,
                label: l10n.searchChannel,
                onTap: () => setState(() {
                  _searching = !_searching;
                  _searchAsked++;
                  if (!_searching) _query.clear();
                }),
              ),
              if (roomy)
                AppIconButton(
                  icon: AppIcons.people,
                  label: _membersBeside
                      ? l10n.hideMemberList
                      : l10n.showMemberList,
                  background: _membersBeside ? AppColors.raised : null,
                  onTap: () => setState(() => _membersBeside = !_membersBeside),
                )
              else
                AppIconButton(
                  icon: AppIcons.people,
                  label: l10n.members,
                  onTap: () => showSpaceMembers(context, space),
                ),
              AppIconButton(
                icon: AppIcons.more,
                label: l10n.moreOptions,
                onTap: () => _menu(space),
              ),
            ],
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: AppTextBox(
                key: ValueKey(_searchAsked),
                autofocus: true,
                controller: _query,
                label: l10n.searchChannel,
                hint: l10n.searchChannelHint(channel.name),
                icon: AppIcons.search,
                height: 46,
                fontSize: 16,
              ),
            ),
          if (pinned != null && !_searching)
            _PinnedStrip(
              text: pinned,
              onTap: () =>
                  _openPinned(pinned, canUnpin: space.may(RolePower.pin)),
            ),
        ],
      ),
      body: messages.isEmpty
          ? Center(
              child: Text(
                query.isEmpty ? l10n.noMessagesYet : l10n.noSearchMatches,
                style: AppText.base.copyWith(color: AppColors.text2),
              ),
            )
          : ThreadView(
              controller: _scroll,
              itemCount: all.length,
              toNewestLabel: l10n.scrollToNewest,
              newCount: firstNew == null ? 0 : _newWhenOpened,
              newLine: _newLine,
              newLabel: firstNew == null
                  ? null
                  : l10n.jumpToNew(_newWhenOpened),
              child: ListView(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                children: [
                  for (final (index, message) in messages.reversed.indexed) ...[
                    // A reaction row ends 6 px lower than it looks, because
                    // its touch targets are taller than its pills.
                    if (index > 0)
                      SizedBox(height: message.reactions.isEmpty ? 16 : 10),
                    _MessageRow(
                      channelId: channelId,
                      message: message,
                      people: people,
                      shared: shared,
                      canReply: canWrite,
                      canPin: space.may(RolePower.pin),
                      canDelete:
                          message.authorId == meId ||
                          space.may(RolePower.delete),
                      onReply: () => setState(() => _replyingTo = message),
                    ),
                    // The list runs upwards, so this sits above the message.
                    if (message.id == firstNew) _NewMessagesLine(key: _newLine),
                  ],
                ],
              ),
            ),
      footer: canWrite && state.recordingVoice
          ? RecordingBar(
              onCancel: state.cancelVoice,
              onSend: () => state.sendChannelVoice(channelId),
            )
          : !canWrite
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
              child: Text(
                keptFor.isNotEmpty && !ownersOnly
                    ? l10n.onlyRolesWrite(keptFor.join(', '))
                    : l10n.onlyOwnerPosts,
                textAlign: TextAlign.center,
                style: AppText.footnote,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (typing != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        typing,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.footnote,
                      ),
                    ),
                  ),
                if (replyingTo != null)
                  _ReplyBar(
                    name: replyingTo.authorId == meId
                        ? state.profileName
                        : state.person(replyingTo.authorId).name,
                    text:
                        replyingTo.text ??
                        replyingTo.poll?.question ??
                        (replyingTo.sticker == null ? '' : l10n.stickerPreview),
                    onCancel: () => setState(() => _replyingTo = null),
                  ),
                // The owner's rules for this channel, so nobody is surprised
                // by a refusal. That messages here disappear binds everyone,
                // the owner too, so everyone is told.
                if (((channel.noLinks ||
                            channel.slowSeconds > 0 ||
                            channel.maxLength > 0 ||
                            space.bannedWords.isNotEmpty) &&
                        !space.iRunIt) ||
                    channel.disappearSeconds > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Text(
                      [
                        if (channel.disappearSeconds > 0)
                          l10n.rulesNoteDisappear(
                            switch (channel.disappearSeconds) {
                              3600 => l10n.timerHour,
                              86400 => l10n.timerDay,
                              _ => l10n.timerWeek,
                            },
                          ),
                        if (channel.noLinks && !space.iRunIt)
                          l10n.rulesNoteNoLinks,
                        if (channel.maxLength > 0 && !space.iRunIt)
                          l10n.rulesNoteLength(channel.maxLength),
                        if (space.bannedWords.isNotEmpty && !space.iRunIt)
                          l10n.rulesNoteBanned,
                        if (channel.slowSeconds > 0 && !space.iRunIt)
                          l10n.rulesNoteSlow(
                            l10n.slowChoice(channel.slowSeconds),
                          ),
                      ].join(' '),
                      style: AppText.footnote,
                    ),
                  ),
                Composer(
                  hint: l10n.messageChannel(channel.name),
                  // The people in the space, but not the user.
                  // And the space's roles, and everyone for whoever may
                  // call on everyone at once.
                  noLinks: channel.noLinks && !space.iRunIt,
                  away: state.myAway,
                  onAway: state.setAway,
                  onBack: state.clearAway,
                  awayNotes: awayNotes,
                  mentionable: [
                    for (final person in members)
                      if (person.id != state.myId)
                        MentionChoice(
                          name: person.name,
                          key: person.id,
                          tone: person.tone,
                          photo: person.photo,
                          tag: shared.contains(person.name.trim().toLowerCase())
                              ? Names.tag(person.id)
                              : null,
                        ),
                    for (final role in space.roleDefs)
                      MentionChoice(name: role.name),
                    if (space.may(RolePower.mentionEveryone))
                      const MentionChoice(name: 'everyone', everyone: true),
                  ],
                  onTyping: () => state.typingInChannel(channelId),
                  onSend: (text) {
                    final refused = state.sendChannelText(
                      channelId,
                      text,
                      replyTo: replyingTo?.id,
                    );
                    if (refused != null) {
                      showAppToast(context, refusalText(l10n, refused));
                      return false;
                    }
                    if (replyingTo != null) setState(() => _replyingTo = null);
                    return true;
                  },
                  onAttach: () => Go.shareSheet(context, channelId: channelId),
                  onSticker:
                      state.canSendChannelStickers &&
                          state.works(Extra.stickers)
                      ? (sticker) {
                          final done = state.sendChannelSticker(
                            channelId,
                            sticker,
                          );
                          if (done.sent) return;
                          showAppToast(context, switch (done.refused) {
                            final refused? => refusalText(l10n, refused),
                            null => l10n.stickerNotSent,
                          });
                        }
                      : null,
                  onRecord: state.canRecordVoice
                      ? () async {
                          if (!await state.startVoice() && context.mounted) {
                            showAppToast(context, l10n.micUnavailable);
                          }
                        }
                      : state.works(Extra.voiceInChannels)
                      ? () => showNotBuiltYet(context)
                      : null,
                ),
              ],
            ),
    );
  }
}

/// Whether [lower], a message in small letters, calls on the person
/// [name] with [key]: "@name", followed by their tag where [shared] has
/// the name, and not just the start of a longer word.
bool _callsOn(String lower, String name, String key, Set<String> shared) {
  final written = '@${name.trim().toLowerCase()}';
  final tagged = shared.contains(name.trim().toLowerCase());
  for (
    var at = lower.indexOf(written);
    at >= 0;
    at = lower.indexOf(written, at + 1)
  ) {
    final end = at + written.length;
    final tag = Names.tagAfter(lower, end);
    if (tagged) {
      if (tag != null && tag.toUpperCase() == Names.tag(key)) return true;
      continue;
    }
    if (end == lower.length ||
        !RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(lower[end])) {
      return true;
    }
  }
  return false;
}

/// Marks where what was new when the channel was opened begins.
class _NewMessagesLine extends StatelessWidget {
  const _NewMessagesLine({super.key});

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.newMessages;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          children: [
            const Expanded(
              child: SizedBox(
                height: 1,
                child: ColoredBox(color: AppColors.red),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: AppText.timestamp.copyWith(color: AppColors.red),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: SizedBox(
                height: 1,
                child: ColoredBox(color: AppColors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sits on the message box while a reply is being written, and says what
/// it will answer.
class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.name,
    required this.text,
    required this.onCancel,
  });

  final String name;
  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          const AppIcon(AppIcons.reply, size: 16, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.replyingTo(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.detail.copyWith(color: AppColors.accent),
                ),
                ExcludeSemantics(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.detail,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: AppIcons.close,
            label: l10n.cancelReply,
            color: AppColors.text2,
            onTap: onCancel,
          ),
        ],
      ),
    );
  }
}

/// The space's members, listed beside a channel on a big window.
class _MemberPane extends StatelessWidget {
  const _MemberPane({required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kMemberPaneWidth,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        left: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
          child: SpaceMemberList(space: space, surround: AppColors.bg),
        ),
      ),
    );
  }
}

class _PinnedStrip extends StatelessWidget {
  const _PinnedStrip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '${context.l10n.pinnedMessage}: $text',
      focusRadius: BorderRadius.zero,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.surface,
        child: Row(
          children: [
            const AppIcon(AppIcons.pin, size: 16, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                plainText(text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            const AppIcon(
              AppIcons.chevronRight,
              size: 16,
              color: AppColors.text3,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.channelId,
    required this.message,
    required this.people,
    required this.shared,
    required this.canReply,
    required this.canPin,
    required this.canDelete,
    required this.onReply,
  });

  final String channelId;
  final ChannelMessage message;

  /// Who an @name in the message may be.
  final List<MentionTarget> people;

  /// The names two members share, in small letters. Each is shown with
  /// its tag.
  final Set<String> shared;

  /// Whether the user may write in this channel at all.
  final bool canReply;

  /// Whether the user runs the space: its owner or an admin.
  final bool canPin;

  /// Whether the user wrote this, or runs the space.
  final bool canDelete;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final mine = message.authorId == meId;
    final author = mine ? null : state.person(message.authorId);
    // A picture from someone who is not a contact is blurred until the
    // user chooses to see it. The app's own stickers are not pictures of
    // anyone's.
    final stranger = !mine && !(author?.isContact ?? false);
    final sticker = message.sticker;
    final keepable =
        sticker != null &&
        sticker.isOwn &&
        state.canKeepStickers &&
        !state.keepsSticker(sticker);

    /// Pressing and holding a message offers what can be done with it. It
    /// is how the first reaction gets onto a message that has none.
    Future<void> act() async {
      final action = await showMessageActions(
        context,
        canReply: canReply,
        canPin: canPin,
        pinned: message.pinned,
        canDelete: canDelete,
        // Only its writer changes a message, and never a poll, whose
        // question was voted on as it was.
        canEdit: mine && message.poll == null && message.text != null,
        // Words are passed on; a poll or a file is not.
        canForward:
            state.works(Extra.forwarding) &&
            message.poll == null &&
            message.file == null &&
            (message.text?.trim().isNotEmpty ?? false),
        onEmoji: state.canReactWithAnyEmoji && state.works(Extra.emojiReactions)
            ? (emoji) => state.toggleChannelEmoji(channelId, message.id, emoji)
            : null,
        onKeepSticker: keepable
            ? () => saveStickerToPack(context, sticker)
            : null,
      );
      switch (action) {
        case null:
          return;
        case MessageAction.heart:
          state.toggleChannelReaction(
            channelId,
            message.id,
            ReactionKind.heart,
          );
        case MessageAction.agree:
          state.toggleChannelReaction(
            channelId,
            message.id,
            ReactionKind.agree,
          );
        case MessageAction.reply:
          onReply();
        case MessageAction.forward:
          if (!context.mounted) return;
          await showForwardSheet(
            context,
            text: message.text!,
            fromChannel: channelId,
          );
        case MessageAction.pin:
          state.setPinned(channelId, message.id, on: true);
        case MessageAction.unpin:
          state.setPinned(channelId, message.id, on: false);
        case MessageAction.delete:
          state.deleteChannelMessage(channelId, message.id);
        case MessageAction.edit:
          if (!context.mounted) return;
          await showAppPrompt(
            context,
            title: l10n.editMessageTitle,
            label: l10n.editMessage,
            action: l10n.save,
            initial: message.text ?? '',
            check: (text) {
              final done = state.editChannelText(channelId, message.id, text);
              if (done.changed) return null;
              final refused = done.refused;
              return refused == null
                  ? l10n.editNotDone
                  : refusalText(l10n, refused);
            },
          );
      }
    }

    // Parts sit 6 px apart, except that a reaction row brings its own
    // spacing inside its 44 px touch targets.
    final parts = <Widget>[];
    var previousTight = false;
    void add(Widget part, {bool tight = false}) {
      if (parts.isNotEmpty && !tight && !previousTight) {
        parts.add(const SizedBox(height: 6));
      }
      parts.add(part);
      previousTight = tight;
    }

    add(
      Row(
        children: [
          Flexible(
            child: Text(
              author == null
                  ? Names.shown(state.profileName, state.myId, shared)
                  : Names.shown(author.name, author.id, shared),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.strong,
            ),
          ),
          if (author?.verified ?? false) ...[
            const SizedBox(width: 6),
            const VerifiedBadge(size: 14),
          ],
          if ((author == null ? state.myAway : author.away)
              case final away?) ...[
            const SizedBox(width: 6),
            AwayMark(note: away),
          ],
          const SizedBox(width: 6),
          Text(message.time, style: AppText.timestamp),
          if (message.edited) ...[
            const SizedBox(width: 6),
            Text(l10n.messageEdited, style: AppText.timestamp),
          ],
          if (message.forwarded) ...[
            const SizedBox(width: 6),
            Text(l10n.messageForwarded, style: AppText.timestamp),
          ],
          if (message.mentionsMe) ...[
            const SizedBox(width: 6),
            Text(
              l10n.mentionsYou,
              style: AppText.timestamp.copyWith(color: AppColors.accent),
            ),
          ],
        ],
      ),
    );
    if (message.replyTo != null) {
      add(
        Row(
          children: [
            const AppIcon(AppIcons.reply, size: 14, color: AppColors.text2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message.replyTo!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.detail,
              ),
            ),
          ],
        ),
      );
    }
    if (message.text case final text?) {
      // A few emoji on their own are shown large.
      final big = message.forwarded ? 0 : bigEmojiCount(text);
      add(
        big > 0
            ? Text(
                text.trim(),
                style: AppText.base.copyWith(
                  fontSize: switch (big) {
                    1 => 48,
                    2 => 40,
                    _ => 32,
                  },
                  height: 1.15,
                ),
              )
            : LinkText(
                text,
                mentions: message.mentions,
                people: people,
                onMention: (key) => showPersonCard(context, key),
              ),
      );
    }
    if (sticker != null) {
      add(
        Align(
          alignment: Alignment.centerLeft,
          child: StrangerBlur(
            key: ValueKey('sticker ${message.id}'),
            blurred: stranger && sticker.isOwn,
            width: 140,
            height: 140,
            child: StickerView(sticker: sticker),
          ),
        ),
      );
    }
    if (message.file != null) {
      add(
        ChannelFileView(
          channelId: channelId,
          messageId: message.id,
          file: message.file!,
          authorId: message.authorId,
        ),
      );
    }
    if (message.location case final place?) {
      add(
        Align(
          alignment: Alignment.centerLeft,
          child: LocationCard(place: place, background: AppColors.surface),
        ),
      );
    }
    if (message.reactions.isNotEmpty) {
      add(
        tight: true,
        // Many emoji go onto more than one line.
        Wrap(
          spacing: 6,
          children: [
            for (final reaction in message.reactions)
              ReactionPill(
                reaction: reaction,
                onTap: () {
                  final state = AppScope.read(context);
                  if (reaction.kind == ReactionKind.emoji) {
                    state.toggleChannelEmoji(
                      channelId,
                      message.id,
                      reaction.emoji,
                    );
                  } else {
                    state.toggleChannelReaction(
                      channelId,
                      message.id,
                      reaction.kind,
                    );
                  }
                },
              ),
          ],
        ),
      );
    }
    if (message.poll != null) {
      add(
        PollCard(
          poll: message.poll!,
          onVote: (option) =>
              AppScope.read(context).votePoll(channelId, message.id, option),
        ),
      );
    }
    if (message.voiceDuration != null) {
      add(
        Align(
          alignment: Alignment.centerLeft,
          child: VoiceNote(
            duration: message.voiceDuration!,
            background: AppColors.surface,
            onPlay: () => showNotBuiltYet(context),
          ),
        ),
      );
    }
    if (message.disappears) {
      add(
        Row(
          children: [
            const AppIcon(AppIcons.timer, size: 12, color: AppColors.text3),
            const SizedBox(width: 6),
            Text(switch (message.endsAt) {
              final ends? => l10n.goneIn(
                ends.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30),
              ),
              null => l10n.goneInOneDay,
            }, style: AppText.timestamp),
          ],
        ),
      );
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: author == null
              ? null
              : () => showPersonCard(context, author.id),
          child: Avatar(
            tone: author?.tone ?? state.myTone,
            photo: author == null ? state.myPhoto : author.photo,
            label: author?.initial ?? state.profileInitial,
            size: 40,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: parts,
          ),
        ),
      ],
    );
    return MessageHover(
      label: l10n.messageMore,
      onActions: act,
      // A message that calls on the user stands out, as in a chat app.
      child: message.mentionsMe
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.channelRow),
              ),
              child: row,
            )
          : row,
    );
  }
}

/// A file, picture or voice message in a channel. Once it is on this
/// device a picture is shown and a voice message plays; until then, and
/// for any other file, it is a card that says what it is.
class ChannelFileView extends StatelessWidget {
  const ChannelFileView({
    super.key,
    required this.channelId,
    required this.messageId,
    required this.file,
    this.wide = false,
    this.authorId,
  });

  final String channelId;
  final String messageId;
  final FileAttachment file;

  /// Who sent it. A picture from someone who is not a contact is blurred
  /// until the user chooses to see it.
  final String? authorId;

  /// A picture as wide as the card it is in, as in a public channel's
  /// posts.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final file = this.file;
    final path = file.path;
    final messageId = this.messageId;
    // Only a picture whose header says it is a sane size is decoded.
    if (file.held &&
        path != null &&
        file.kind == FileKind.picture &&
        soundImageFile(path)) {
      final author = authorId;
      final stranger =
          author != null &&
          author != meId &&
          !(state.findPerson(author)?.isContact ?? false);
      return Align(
        alignment: Alignment.centerLeft,
        child: StrangerBlur(
          key: ValueKey(messageId),
          blurred: stranger,
          width: wide ? double.infinity : 240,
          height: wide ? 150 : 180,
          child: GestureDetector(
            onTap: () => Go.photo(context, path: path, name: file.name),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.smallButton),
              child: Image.file(
                File(path),
                width: wide ? double.infinity : 240,
                height: wide ? 150 : 180,
                fit: BoxFit.cover,
                // A phone photo is far bigger than this; do not hold all of
                // it in memory.
                cacheWidth: 720,
                semanticLabel: file.name,
                errorBuilder: (_, _, _) => _FileCard(file: file),
              ),
            ),
          ),
        ),
      );
    }
    if (file.held && path != null && file.kind == FileKind.video) {
      final author = authorId;
      final stranger =
          author != null &&
          author != meId &&
          !(state.findPerson(author)?.isContact ?? false);
      return Align(
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = wide ? box.maxWidth : 240.0;
            return StrangerBlur(
              key: ValueKey(messageId),
              blurred: stranger,
              width: width,
              height: width / 1.5,
              child: VideoView(
                path: path,
                name: file.name,
                seconds: file.seconds,
                width: width,
              ),
            );
          },
        ),
      );
    }
    if (file.held && path != null && file.kind == FileKind.voice) {
      return Align(
        alignment: Alignment.centerLeft,
        child: VoiceNote(
          duration: formatSeconds(file.seconds),
          background: AppColors.surface,
          playedBars: 0,
          onPlay: () => state.toggleVoice(path, seconds: file.seconds),
        ),
      );
    }
    return _FileCard(
      file: file,
      onFetch: () => state.fetchChannelFile(channelId, messageId),
      onSave: () {
        final l10n = context.l10n;
        final saved = state.saveChannelFile(channelId, messageId);
        if (saved == null) {
          showAppToast(context, l10n.fileNotSaved);
        } else {
          showAppNotice(context, title: l10n.fileSavedAtTitle, body: saved);
        }
      },
    );
  }
}

/// A file as a card: what it is and how big. One that is here is saved
/// by pressing it; one that is not says how to get it, or how it is
/// coming.
class _FileCard extends StatelessWidget {
  const _FileCard({required this.file, this.onFetch, this.onSave});

  final FileAttachment file;
  final VoidCallback? onFetch;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final radius = BorderRadius.circular(AppRadius.smallButton);
    final icon = switch (file.kind) {
      FileKind.picture => AppIcons.photo,
      FileKind.video => AppIcons.video,
      FileKind.voice => AppIcons.mic,
      FileKind.file => AppIcons.file,
    };
    final status = file.held
        ? null
        : file.wanted
        ? (file.progress > 0
              ? l10n.fileComing((file.progress * 100).floor())
              : l10n.fileWaitingForHolder)
        : null;
    final card = Container(
      // Pressed to save a copy, so at least as tall as a finger needs.
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: radius),
      child: Row(
        children: [
          AppIcon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.base.copyWith(fontWeight: FontWeight.w600),
                ),
                if (status != null) Text(status, style: AppText.detail),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // A video says how long it runs before it is fetched.
          Text(
            file.kind == FileKind.video && file.seconds > 0
                ? '${formatSeconds(file.seconds)} · ${file.size}'
                : file.size,
            style: AppText.detail,
          ),
          if (!file.held && !file.wanted && onFetch != null) ...[
            const SizedBox(width: 6),
            AppButton(
              label: l10n.download,
              height: 44,
              horizontalPadding: 12,
              onTap: onFetch,
            ),
          ],
        ],
      ),
    );
    if (!file.held || onSave == null) return card;
    return Semantics(
      button: true,
      hint: l10n.saveACopy,
      child: Pressable(onTap: onSave, focusRadius: radius, child: card),
    );
  }
}

/// A poll: its question, a bar for each choice, and how many voted.
class PollCard extends StatelessWidget {
  const PollCard({
    super.key,
    required this.poll,
    required this.onVote,
    this.footer,
  });

  final Poll poll;
  final ValueChanged<int> onVote;

  /// What to say under the bars. In a space it is the count and that the
  /// app does not show who voted. Between two people that would be silly.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(poll.question, style: AppText.strong),
          for (final (index, option) in poll.options.indexed) ...[
            const SizedBox(height: 8),
            _PollOptionBar(
              label: option.label,
              percent: poll.percentFor(index),
              chosen: index == poll.myChoice,
              onTap: () => onVote(index),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            footer ?? l10n.pollFooter(poll.totalVotes),
            style: AppText.base.copyWith(fontSize: 12, color: AppColors.text2),
          ),
        ],
      ),
    );
  }
}

class _PollOptionBar extends StatelessWidget {
  const _PollOptionBar({
    required this.label,
    required this.percent,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final int percent;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.channelRow);
    return Pressable(
      onTap: onTap,
      selected: chosen,
      focusRadius: radius,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          color: AppColors.raised,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent / 100,
                  child: ColoredBox(
                    color: chosen ? AppColors.ownBubble : AppColors.pollBar,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: AppText.base.copyWith(
                                fontWeight: chosen
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (chosen) ...[
                            const SizedBox(width: 6),
                            const AppIcon(AppIcons.check, size: 14),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      context.l10n.percent(percent),
                      style: AppText.base.copyWith(
                        fontSize: 13,
                        color: chosen ? AppColors.text : AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A picture from someone who is not a contact: blurred, with a word on
/// why, until the user taps to see it. Seen once, it stays seen while the
/// screen is open.
class StrangerBlur extends StatefulWidget {
  const StrangerBlur({
    super.key,
    required this.blurred,
    required this.width,
    required this.height,
    required this.child,
  });

  final bool blurred;
  final double width;
  final double height;
  final Widget child;

  @override
  State<StrangerBlur> createState() => _StrangerBlurState();
}

class _StrangerBlurState extends State<StrangerBlur> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.blurred || _shown) return widget.child;
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: '${l10n.fromStranger}. ${l10n.tapToShow}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => setState(() => _shown = true),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.smallButton),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: IgnorePointer(child: widget.child),
                ),
                ColoredBox(
                  color: AppColors.bg.withValues(alpha: 0.45),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const AppIcon(
                        AppIcons.warning,
                        size: 22,
                        color: AppColors.text,
                      ),
                      const SizedBox(height: 6),
                      Text(l10n.fromStranger, style: AppText.strong),
                      Text(l10n.tapToShow, style: AppText.detail),
                    ],
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
