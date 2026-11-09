import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../data/safe_file.dart';
import '../data/app_state.dart';
import '../data/image_bounds.dart';
import '../data/live_directory.dart';
import '../data/emoji.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/extra_icons.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/action_list.dart';
import 'call_screen.dart' show startCall;
import 'channel_screen.dart' show PollCard;
import 'space_sheets.dart' show showForwardSheet;
import '../widgets/link_text.dart';
import '../widgets/location_card.dart';
import '../widgets/avatar.dart';
import '../widgets/badges.dart';
import '../widgets/buttons.dart';
import '../widgets/composer.dart';
import '../widgets/feedback.dart';
import '../widgets/person_card.dart' show awayNote;
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import '../widgets/sticker_view.dart';
import '../widgets/thread.dart';
import '../widgets/video_view.dart';
import '../widgets/voice_note.dart';

/// 06 Direct message. A one-to-one chat, or the Saved messages notes chat
/// when [chatId] is [savedMessagesId].
class DirectMessageScreen extends StatefulWidget {
  const DirectMessageScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<DirectMessageScreen> createState() => _DirectMessageScreenState();
}

class _DirectMessageScreenState extends State<DirectMessageScreen> {
  bool get _saved => widget.chatId == savedMessagesId;

  bool _markingRead = false;

  /// The thread, so the user can be brought back down to the newest.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _typingFade?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Having the chat open reads it, including what arrives while it is
  /// open. Done after the frame, so the list behind is not rebuilt while
  /// this screen is still being built.
  void _readWhatArrived(AppState state) {
    if (_saved || _markingRead) return;
    final unread = state.chats.any(
      (c) => c.personId == widget.chatId && c.unread > 0,
    );
    if (!unread) return;
    _markingRead = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markingRead = false;
      if (mounted) AppScope.read(context).markChatRead(widget.chatId);
    });
  }

  /// Redraws once "typing" has had time to go quiet, since nothing else
  /// may happen to make the screen look again.
  Timer? _typingFade;

  String _linkLabel(AppLocalizations l10n, AppState state, Person person) {
    if (state.isTyping(person.id)) {
      _typingFade ??= Timer(
        LiveDirectory.typingFor + const Duration(milliseconds: 200),
        () {
          _typingFade = null;
          if (mounted) setState(() {});
        },
      );
      return l10n.typingNow;
    }
    final link = person.link;
    return switch (link.kind) {
      // Whichever link is roomier carries the chat while it is there.
      LinkKind.wifi => l10n.nearbyOnWifi,
      LinkKind.bluetooth => l10n.nearbyOnBluetooth,
      LinkKind.radio => l10n.nearbyByRadio,
      LinkKind.relayed => l10n.reachedThroughHops(
        link.hops,
        state.person(link.viaId!).name,
      ),
      LinkKind.outOfRange => l10n.outOfRange,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    _readWhatArrived(state);
    final person = _saved ? null : state.person(widget.chatId);
    final items = state.thread(widget.chatId);
    final name = person?.name ?? l10n.savedMessages;

    return AppScreen(
      header: AppTopBar(
        divider: true,
        leading: person == null
            ? const Avatar(
                tone: AvatarTone.grey,
                icon: AppIcons.bookmark,
                size: 38,
              )
            : Avatar(
                tone: person.tone,
                photo: person.photo,
                label: person.initial,
                size: 38,
                online: person.online,
              ),
        title: name,
        titleTrailing: person == null
            ? null
            : person.verified
            ? const VerifiedBadge()
            : Pressable(
                onTap: () => Go.verify(context, person.id),
                semanticLabel: l10n.verifyPerson(person.name),
                focusRadius: BorderRadius.circular(AppRadius.chip),
                child: AppChip(l10n.notVerified, tone: ChipTone.amber),
              ),
        subtitle: person == null
            ? l10n.onlyOnThisPhone(context.deviceKind)
            : _linkLabel(l10n, state, person),
        // Calls start from here, not from the "more" menu.
        actions: [
          if (person != null && state.works(Extra.calls))
            AppIconButton(
              icon: AppIcons.phone,
              label: l10n.callPerson(person.name),
              onTap: () => startCall(context, person.id),
            ),
          if (person != null && state.works(Extra.videoCalls))
            AppIconButton(
              icon: AppIcons.video,
              label: l10n.videoCallPerson(person.name),
              onTap: () => startCall(context, person.id, video: true),
            ),
          // A note to oneself has nothing more to offer.
          if (person != null)
            AppIconButton(
              icon: AppIcons.more,
              label: l10n.moreOptions,
              onTap: () => _menu(person),
            ),
        ],
      ),
      // Reversed, so the newest message sits at the bottom and a short
      // thread hugs the composer.
      body: ThreadView(
        controller: _scroll,
        itemCount: items.length,
        toNewestLabel: l10n.scrollToNewest,
        child: ListView(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            for (final (index, item) in items.reversed.indexed) ...[
              if (index > 0) const SizedBox(height: 10),
              _item(context, item),
            ],
            if (person != null) ...[
              const SizedBox(height: 16),
              const Center(child: _EncryptedNote()),
              // A name the user already had, on a key they had not: not
              // verified until they compare words again.
              if (!person.verified && state.sameNameAs(person.id) != null) ...[
                const SizedBox(height: 12),
                _KeyChangedNote(person: person),
              ],
            ],
          ],
        ),
      ),
      footer: state.recordingVoice
          ? RecordingBar(
              onCancel: state.cancelVoice,
              onSend: () => state.sendVoice(widget.chatId),
            )
          : Composer(
              hint: l10n.messagePerson(name),
              onSend: (text) => state.sendDirectText(widget.chatId, text),
              // ".afk lunch" marks the user away; whoever they write to
              // that is away is said to be, once the message has gone.
              away: state.myAway,
              onAway: state.setAway,
              onBack: state.clearAway,
              awayNotes: _saved
                  ? null
                  : (_) => [
                      if (state.person(widget.chatId).away case final away?)
                        awayNote(l10n, name, away),
                    ],
              onTyping: _saved ? null : () => state.typingIn(widget.chatId),
              // There is nothing to attach to a note to oneself yet.
              onAttach: _saved && !state.works(Extra.filesInChannels)
                  ? null
                  : () => Go.shareSheet(context, chatId: widget.chatId),
              onRecord: _saved && !state.works(Extra.voiceInChannels)
                  ? null
                  : _record,
              // Stickers go to a person; notes to oneself have none.
              onSticker: _saved || !state.works(Extra.stickers)
                  ? null
                  : (sticker) {
                      if (!state.sendSticker(widget.chatId, sticker)) {
                        showAppToast(context, l10n.stickerNotSent);
                      }
                    },
            ),
    );
  }

  /// Pressing and holding a message: delete it for me, or, if the user
  /// wrote it lately, for everyone. A sticker of someone's own can be
  /// kept.
  Future<void> _messageActions(DirectText message) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final sticker = message.sticker;
    final keepable =
        sticker != null &&
        sticker.isOwn &&
        state.canKeepStickers &&
        !state.keepsSticker(sticker);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (keepable) ...[
            AppButton(
              label: l10n.saveAsSticker,
              icon: ExtraIcons.sticker,
              onTap: () => Navigator.of(context).pop('keep'),
            ),
            const SizedBox(height: 10),
          ],
          // Words are passed on; a sticker is not.
          if (state.works(Extra.forwarding) && sticker == null) ...[
            AppButton(
              label: l10n.forwardMessage,
              icon: ExtraIcons.send,
              onTap: () => Navigator.of(context).pop('forward'),
            ),
            const SizedBox(height: 10),
          ],
          if (message.canDeleteForEveryone) ...[
            AppButton(
              label: l10n.deleteForEveryone,
              icon: ExtraIcons.trash,
              kind: AppButtonKind.dangerText,
              onTap: () => Navigator.of(context).pop('everyone'),
            ),
            const SizedBox(height: 10),
          ],
          AppButton(
            label: l10n.deleteForMe,
            icon: ExtraIcons.trash,
            onTap: () => Navigator.of(context).pop('me'),
          ),
          if (message.canDeleteForEveryone) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(l10n.deleteForEveryoneNote, style: AppText.detail),
            ),
          ],
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'keep') {
      await saveStickerToPack(context, sticker!);
      return;
    }
    if (choice == 'forward') {
      await showForwardSheet(
        context,
        text: message.text,
        fromChat: widget.chatId,
      );
      return;
    }
    if (choice == 'everyone') {
      if (!state.deleteForEveryone(widget.chatId, [message.id])) {
        showAppToast(context, l10n.deleteForEveryoneFailed);
      }
    } else {
      state.deleteForMe(widget.chatId, [message.id]);
    }
  }

  /// The "more" button: who this is, then verifying, disappearing messages
  /// and clearing, and apart from those, the two that cannot be undone.
  /// Calls are in the top bar.
  Future<void> _menu(Person person) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final timer = switch (state.chatTimer(person.id)) {
      0 => l10n.timerOffShort,
      3600 => l10n.timerHour,
      86400 => l10n.timerDay,
      604800 => l10n.timerWeek,
      _ => null,
    };
    final choice = await showAppSheet<String>(
      context,
      builder: (context) {
        void choose(String key) => Navigator.of(context).pop(key);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuHeader(person: person),
            const SizedBox(height: 16),
            ActionGroup(
              actions: [
                SheetAction(
                  icon: AppIcons.verified,
                  label: l10n.verifyTitle(person.name),
                  onTap: () => choose('verify'),
                ),
                SheetAction(
                  icon: AppIcons.timer,
                  label: l10n.disappearingMessages,
                  value: timer,
                  onTap: () => choose('timer'),
                ),
                SheetAction(
                  icon: _eraserIcon,
                  label: l10n.clearChat,
                  onTap: () => choose('clear'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ActionGroup(
              actions: [
                SheetAction(
                  icon: ExtraIcons.trash,
                  label: l10n.deleteChat,
                  danger: true,
                  onTap: () => choose('delete'),
                ),
                SheetAction(
                  icon: _blockIcon,
                  label: l10n.blockPerson,
                  danger: true,
                  onTap: () => choose('block'),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == 'verify') {
      Go.verify(context, person.id);
      return;
    }
    if (choice == 'clear') {
      final sure = await showAppConfirm(
        context,
        title: l10n.clearChatConfirmTitle(person.name),
        body: l10n.clearChatConfirmBody(person.name),
        confirmLabel: l10n.clear,
        destructive: true,
      );
      if (sure) state.clearChat(person.id);
      return;
    }
    if (choice == 'delete') {
      final navigator = Navigator.of(context);
      final sure = await showAppConfirm(
        context,
        title: l10n.deleteChatConfirmTitle(person.name),
        body: l10n.deleteChatConfirmBody(person.name),
        confirmLabel: l10n.delete,
        destructive: true,
      );
      if (!sure) return;
      state.deleteChat(person.id);
      navigator.pop();
      return;
    }
    if (choice == 'timer') {
      final seconds = await showAppSheet<int>(
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
                  l10n.disappearingMessages,
                  style: AppText.base.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(l10n.disappearingBody, style: AppText.detail),
            ),
            const SizedBox(height: 14),
            for (final (seconds, label) in [
              (0, l10n.timerOff),
              (60 * 60, l10n.timerHour),
              (24 * 60 * 60, l10n.timerDay),
              (7 * 24 * 60 * 60, l10n.timerWeek),
            ]) ...[
              AppButton(
                label: label,
                height: 46,
                // The one in force now is the filled one.
                kind: state.chatTimer(person.id) == seconds
                    ? AppButtonKind.primary
                    : AppButtonKind.secondary,
                onTap: () => Navigator.of(context).pop(seconds),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      );
      if (seconds != null) state.setChatTimer(person.id, seconds);
      return;
    }
    if (choice != 'block') return;
    final sure = await showAppConfirm(
      context,
      title: l10n.blockConfirmTitle(person.name),
      body: l10n.blockConfirmBody,
      confirmLabel: l10n.block,
      destructive: true,
    );
    if (!sure || !mounted) return;
    Navigator.of(context).pop();
    state.blockPerson(person.id);
  }

  /// Starts a voice message for the person in this chat.
  Future<void> _record() async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    // A note to oneself, and a device with no microphone the app can
    // use, have no voice messages.
    if (_saved || !state.canRecordVoice) {
      showNotBuiltYet(context);
      return;
    }
    if (!await state.startVoice() && mounted) {
      showAppToast(context, l10n.micUnavailable);
    }
  }

  Widget _item(BuildContext context, DirectItem item) {
    final (mine, child) = switch (item) {
      DirectText() => (
        item.mine,
        MessageHover(
          label: context.l10n.messageMore,
          beside: item.mine ? AxisDirection.left : AxisDirection.right,
          // Notes to self have no "for everyone", and a deleted message
          // has nothing left to act on.
          onActions: _saved || item.deleted || item.id.isEmpty
              ? null
              : () => _messageActions(item),
          child: _TextBubble(item, marks: !_saved),
        ),
      ),
      DirectPoll() => (
        item.mine,
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ThreadWidth.of(context, 300)),
          child: PollCard(
            poll: item.poll,
            footer: context.l10n.votesCount(item.poll.totalVotes),
            onVote: (option) =>
                AppScope.read(context)
                    .voteDirectPoll(widget.chatId, item.id, option),
          ),
        ),
      ),
      DirectVoice() => (
        item.mine,
        VoiceNote(
          duration: item.duration,
          onPlay: () => showNotBuiltYet(context),
        ),
      ),
      DirectCard() => (item.mine, _CardBubble(item)),
      DirectLocation() => (
        item.mine,
        MessageHover(
          label: context.l10n.messageMore,
          beside: item.mine ? AxisDirection.left : AxisDirection.right,
          // The same choices as for words: the place in words is what is
          // passed on, and it can be deleted like any message.
          onActions: item.id.isEmpty
              ? null
              : () => _messageActions(
                  DirectText(
                    id: item.id,
                    text: item.place.text,
                    time: item.time,
                    mine: item.mine,
                    canDeleteForEveryone: item.canDeleteForEveryone,
                  ),
                ),
          child: _LocationBubble(item),
        ),
      ),
      DirectPhoto() => (item.mine, _PhotoBubble(item)),
      DirectFile() => (item.mine, _FileBubble(item)),
    };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }
}

/// Clearing a chat: its messages go, the chat stays.
const _eraserIcon = AppIconData([
  IconPath('m15 4 5 5-9 9H7l-3-3 11-11Z'),
  IconPath('m9.5 9.5 5 5'),
  IconPath('M12 20h8'),
]);

/// Blocking someone.
const _blockIcon = AppIconData([
  IconCircle(12, 12, 9),
  IconPath('m5.6 5.6 12.8 12.8'),
]);

/// The top of the chat's "more" sheet: who the chat is with, and whether
/// they are verified.
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Row(
        children: [
          Avatar(
            tone: person.tone,
            photo: person.photo,
            label: person.initial,
            size: 48,
            surround: AppColors.surface,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.base.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                    if (person.verified) ...[
                      const SizedBox(width: 6),
                      const VerifiedBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  person.verified ? l10n.verified : l10n.notVerified,
                  style: AppText.detail.copyWith(
                    color: person.verified ? AppColors.green : AppColors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Said in a chat with someone who goes by a contact's name on a
/// different key, until they are verified.
class _KeyChangedNote extends StatelessWidget {
  const _KeyChangedNote({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Pressable(
      onTap: () => Go.verify(context, person.id),
      semanticLabel: l10n.keyChangedTitle(person.name),
      focusRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.amberSoft,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppIcon(AppIcons.warning, size: 20, color: AppColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.keyChangedTitle(person.name),
                    style: AppText.rowTitle.copyWith(color: AppColors.amber),
                  ),
                  const SizedBox(height: 2),
                  Text(l10n.keyChangedBody(person.name), style: AppText.detail),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EncryptedNote extends StatelessWidget {
  const _EncryptedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.smallButton),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(AppIcons.lock, size: 14, color: AppColors.green),
          const SizedBox(width: 8),
          Flexible(
            child: Text(context.l10n.encryptedNote, style: AppText.detail),
          ),
        ],
      ),
    );
  }
}

BorderRadius _bubbleRadius({required bool mine}) => BorderRadius.only(
  topLeft: const Radius.circular(20),
  topRight: const Radius.circular(20),
  bottomRight: Radius.circular(mine ? 6 : 20),
  bottomLeft: Radius.circular(mine ? 20 : 6),
);

class _TextBubble extends StatelessWidget {
  const _TextBubble(this.message, {required this.marks});

  final DirectText message;

  /// Show how far the message has got. Notes to self go nowhere, so they
  /// have nothing to show.
  final bool marks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mine = message.mine;
    final sticker = message.deleted ? null : message.sticker;
    final big = message.deleted || message.forwarded
        ? 0
        : bigEmojiCount(message.text);
    if (sticker != null || big > 0) {
      return Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sticker != null)
            StickerView(sticker: sticker)
          else
            Text(
              message.text.trim(),
              style: AppText.base.copyWith(
                fontSize: switch (big) {
                  1 => 52,
                  2 => 42,
                  _ => 34,
                },
                height: 1.15,
              ),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: _metaRow(l10n, AppColors.text2),
          ),
        ],
      );
    }
    final metaColor = mine ? AppColors.ownBubbleMeta : AppColors.text2;
    final meta = AppText.base.copyWith(fontSize: 12, color: metaColor);
    return Container(
      constraints: BoxConstraints(maxWidth: ThreadWidth.of(context, 280)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.ownBubble : AppColors.raised,
        borderRadius: _bubbleRadius(mine: mine),
      ),
      // As wide as the longer of the text and the line under it, with the
      // text on the left and that line on the right.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message.deleted)
              Text(
                mine ? l10n.messageDeletedMine : l10n.messageDeleted,
                style: AppText.base.copyWith(
                  fontStyle: FontStyle.italic,
                  color: metaColor,
                ),
              )
            else ...[
              if (message.forwarded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      AppIcon(ExtraIcons.send, size: 12, color: metaColor),
                      const SizedBox(width: 4),
                      Text(
                        l10n.messageForwarded,
                        style: meta.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              LinkText(message.text),
            ],
            const SizedBox(height: 2),
            _metaRow(l10n, metaColor),
          ],
        ),
      ),
    );
  }

  /// When it was sent, how long it has left, and for the user's own, how
  /// far it has got.
  Widget _metaRow(AppLocalizations l10n, Color metaColor) {
    final meta = AppText.base.copyWith(fontSize: 12, color: metaColor);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.disappears) ...[
          AppIcon(AppIcons.timer, size: 13, color: metaColor),
          const SizedBox(width: 6),
          Text(l10n.goneIn(message.goneInSeconds), style: meta),
          const SizedBox(width: 6),
        ],
        // Went by a LoRa radio: how far the radio says it got.
        if (message.radioStatus case final status?) ...[
          Text(l10n.radioMessageStatus(status.name), style: meta),
          const SizedBox(width: 6),
        ],
        Text(message.time, style: meta),
        // How far the user's own message has got: still on this
        // device, on theirs, or read.
        if (message.mine && marks) ...[
          const SizedBox(width: 6),
          if (message.read)
            AppIcon(
              AppIcons.read,
              size: 16,
              color: AppColors.ownBubbleTick,
              semanticLabel: l10n.read,
            )
          else if (message.delivered)
            AppIcon(
              AppIcons.check,
              size: 14,
              color: metaColor,
              semanticLabel: l10n.delivered,
            )
          else
            AppIcon(
              AppIcons.timer,
              size: 13,
              color: metaColor,
              semanticLabel: l10n.waitingToDeliver,
            ),
        ],
      ],
    );
  }
}

/// A file in the chat: what it is, how far it has got, and for one that
/// is being offered to the user, the two answers.
/// Takes the place of the message box while a voice message is being
/// recorded: how long it has run, and the two ways to end it.
/// Stands in for the message box while a voice message is being recorded.
class RecordingBar extends StatefulWidget {
  const RecordingBar({super.key, required this.onCancel, required this.onSend});

  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final running = AppScope.of(context).recordingFor.inSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      l10n.recordingVoice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.strong,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Text(formatSeconds(running), style: AppText.detail),
                  ),
                ],
              ),
            ),
          ),
          AppButton(
            label: l10n.cancel,
            height: 44,
            horizontalPadding: 14,
            onTap: widget.onCancel,
          ),
          const SizedBox(width: 8),
          AppButton(
            label: l10n.sendVoice,
            kind: AppButtonKind.primary,
            height: 44,
            horizontalPadding: 18,
            onTap: widget.onSend,
          ),
        ],
      ),
    );
  }
}

/// Where someone was, with when it was sent and how far it got.
class _LocationBubble extends StatelessWidget {
  const _LocationBubble(this.location);

  final DirectLocation location;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mine = location.mine;
    final metaColor = mine ? AppColors.ownBubbleMeta : AppColors.text2;
    final meta = AppText.base.copyWith(fontSize: 12, color: metaColor);
    return LocationCard(
      place: location.place,
      background: mine ? AppColors.ownBubble : AppColors.raised,
      metaColor: metaColor,
      borderRadius: _bubbleRadius(mine: mine),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(location.time, style: meta),
          if (mine) ...[
            const SizedBox(width: 6),
            if (location.read)
              AppIcon(
                AppIcons.read,
                size: 16,
                color: AppColors.ownBubbleTick,
                semanticLabel: l10n.read,
              )
            else if (location.delivered)
              AppIcon(
                AppIcons.check,
                size: 14,
                color: metaColor,
                semanticLabel: l10n.delivered,
              )
            else
              AppIcon(
                AppIcons.timer,
                size: 13,
                color: metaColor,
                semanticLabel: l10n.waitingToDeliver,
              ),
          ],
        ],
      ),
    );
  }
}

/// A contact someone passed on, with a button to ask them for a chat.
class _CardBubble extends StatelessWidget {
  const _CardBubble(this.card);

  final DirectCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final mine = card.mine;
    final metaColor = mine ? AppColors.ownBubbleMeta : AppColors.text2;
    final meta = AppText.base.copyWith(fontSize: 12, color: metaColor);
    final where = state.cardState(card);
    return Container(
      constraints: BoxConstraints(maxWidth: ThreadWidth.of(context, 280)),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mine ? AppColors.ownBubble : AppColors.raised,
        borderRadius: _bubbleRadius(mine: mine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                tone: toneForKey(card.personId),
                label: card.name.isEmpty ? '' : card.name.characters.first,
                size: 40,
                surround: mine ? AppColors.ownBubble : AppColors.raised,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.contactCard, style: meta),
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The sender already has this person. Whoever receives the
          // card may ask them, once.
          if (!mine && where == CardState.canAsk)
            AppButton(
              label: l10n.askToChat,
              kind: AppButtonKind.primary,
              height: 40,
              onTap: () {
                if (!state.askFromCard(card)) {
                  showAppToast(context, l10n.cardNotSent);
                }
              },
            )
          else
            Text(switch (where) {
              CardState.asked => l10n.cardAsked,
              CardState.you => l10n.cardIsYou,
              _ => l10n.cardInChats,
            }, style: meta),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(card.time, style: meta),
          ),
        ],
      ),
    );
  }
}

class _FileBubble extends StatelessWidget {
  const _FileBubble(this.file);

  final DirectFile file;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final mine = file.mine;
    // A voice message that is all here is played, not opened.
    final voice = file.voiceSeconds;
    if (voice != null && file.state == FileState.done && file.path.isNotEmpty) {
      return VoiceNote(
        duration: formatSeconds(voice),
        background: mine ? AppColors.ownBubble : AppColors.raised,
        playedBars: 0,
        onPlay: () => state.toggleVoice(file.path, seconds: voice),
      );
    }
    final metaColor = mine ? AppColors.ownBubbleMeta : AppColors.text2;
    final meta = AppText.base.copyWith(fontSize: 12, color: metaColor);
    final status = switch (file.state) {
      FileState.asked => l10n.fileAsked,
      FileState.offered => l10n.fileWaitingForAnswer,
      FileState.moving => l10n.percent(file.percent),
      FileState.paused => l10n.paused,
      // A picture to be seen once says whether it has been.
      FileState.done when file.once =>
        file.viewed
            ? l10n.viewOnceOpened
            : mine
            ? l10n.viewOnceNotOpened
            : l10n.viewOnceTapToOpen,
      FileState.done => mine ? l10n.fileSent : l10n.fileSaved,
      FileState.declined => l10n.fileDeclined,
      FileState.cancelled => l10n.fileCancelled,
      FileState.failed => l10n.fileFailed,
    };
    final radius = _bubbleRadius(mine: mine);

    // Only a picture whose header says it is a sane size is decoded.
    final picture = file.showsPicture && soundImageFile(file.path);
    final video =
        file.isVideo &&
        file.state == FileState.done &&
        file.path.isNotEmpty &&
        !file.once;
    final VoidCallback? onTap;
    if (video) {
      // It plays where it is, or full screen from its own button.
      onTap = null;
    } else if (file.canOpenOnce) {
      // Shown this one time. It is read into memory, deleted from the
      // device and the sender told, and only then shown: so closing the
      // app with it open does not leave it to be opened again.
      onTap = () {
        final Uint8List bytes;
        try {
          bytes = File(file.path).readAsBytesSync();
        } on FileSystemException {
          showAppToast(context, l10n.photoCannotBeShown);
          return;
        }
        state.viewedOnce(file.id);
        Go.photo(context, path: '', name: l10n.viewOncePhoto, once: bytes);
      };
    } else if (file.once) {
      onTap = file.state.active && file.state != FileState.asked
          ? () => Go.fileTransfer(context)
          : null;
    } else if (picture) {
      onTap = () => Go.photo(context, path: file.path, name: file.name);
    } else if (file.state == FileState.done && !mine) {
      // Another app has to open it, so say where it is.
      onTap = () =>
          showAppNotice(context, title: l10n.fileSavedAtTitle, body: file.path);
    } else if (file.state.active && file.state != FileState.asked) {
      onTap = () => Go.fileTransfer(context);
    } else {
      onTap = null;
    }

    return Pressable(
      onTap: onTap,
      semanticLabel: file.once
          ? '${l10n.viewOncePhoto}. $status'
          : picture
          ? '${l10n.photoNamed(file.name)}. $status'
          : video
          ? '${l10n.videoNamed(file.name)}. $status'
          : '${file.name}, ${formatBytes(file.size)}. $status',
      focusRadius: radius,
      child: Container(
        constraints: BoxConstraints(maxWidth: ThreadWidth.of(context, 280)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.ownBubble : AppColors.raised,
          borderRadius: radius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (picture) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.smallButton),
                child: Image.file(
                  File(file.path),
                  width: 252,
                  height: 200,
                  fit: BoxFit.cover,
                  // A phone photo is far bigger than the bubble; do not
                  // hold all of it in memory.
                  cacheWidth: 756,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (video) ...[
              VideoView(path: file.path, name: file.name, width: 252),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  file.once
                      ? AppIcons.timer
                      : picture
                      ? AppIcons.photo
                      : file.isVideo
                      ? AppIcons.video
                      : AppIcons.file,
                  size: 22,
                  color: metaColor,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // What it is called is not shown for a picture
                        // meant to leave nothing behind.
                        file.once
                            ? l10n.viewOncePhoto
                            : voice == null
                            ? file.name
                            : l10n.voiceMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.strong,
                      ),
                      Text(formatBytes(file.size), style: meta),
                    ],
                  ),
                ),
              ],
            ),
            if (!mine && isRiskyFile(file.name)) ...[
              const SizedBox(height: 6),
              Text(
                l10n.riskyFileWarning,
                style: AppText.detail.copyWith(color: AppColors.amber),
              ),
            ],
            const SizedBox(height: 6),
            Text(status, style: meta),
            if (file.state == FileState.asked && !mine) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: l10n.accept,
                    kind: AppButtonKind.primary,
                    height: 44,
                    horizontalPadding: 16,
                    onTap: () => state.answerFile(file.id, accept: true),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: l10n.decline,
                    height: 44,
                    horizontalPadding: 16,
                    onTap: () => state.answerFile(file.id, accept: false),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: Text(file.time, style: meta),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for a photo until real media exists.
class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble(this.message);

  final DirectPhoto message;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final metaColor = mine ? AppColors.ownBubbleMeta : AppColors.text2;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.ownBubble : AppColors.raised,
        borderRadius: _bubbleRadius(mine: mine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            height: 96,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.photo, size: 28, color: metaColor),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.photo,
                    style: AppText.detail.copyWith(color: metaColor),
                  ),
                ],
              ),
            ),
          ),
          Text(
            message.time,
            style: AppText.base.copyWith(fontSize: 12, color: metaColor),
          ),
        ],
      ),
    );
  }
}
