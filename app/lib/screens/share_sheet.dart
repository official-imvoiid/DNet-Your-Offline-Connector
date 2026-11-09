import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../data/place.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/app_switch.dart';
import '../widgets/pressable.dart';
import '../data/video_probe.dart';
import 'space_sheets.dart';

/// 09 Share sheet. Opens over a chat or channel from the plus button.
class ShareSheet extends StatelessWidget {
  const ShareSheet({super.key, this.chatId, this.channelId});

  /// The direct chat this was opened from, or null in a channel.
  final String? chatId;

  /// The channel this was opened from, or null in a direct chat.
  final String? channelId;

  /// Starts a voice message for the person in this chat. The chat shows
  /// the recording once this sheet has closed.
  Future<void> _voice(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    if (!state.canRecordVoice) {
      showNotBuiltYet(context);
      return;
    }
    navigator.pop();
    if (!await state.startVoice() && navigator.mounted) {
      showAppToast(navigator.context, l10n.micUnavailable);
    }
  }

  /// Lets the user choose one of their other contacts and sends it to
  /// the person in this chat as a card.
  Future<void> _contact(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final chat = chatId!;
    final others = [
      for (final person in state.contacts)
        if (person.id != chat) person,
    ];
    final chosen = await showAppSheet<String>(
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
                l10n.chooseContactTitle(state.person(chat).name),
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
              others.isEmpty ? l10n.noOtherContacts : l10n.chooseContactBody,
              style: AppText.detail,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final person in others)
                  Pressable(
                    onTap: () => Navigator.of(context).pop(person.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Avatar(
                            tone: person.tone,
                            label: person.initial,
                            size: 40,
                            surround: AppColors.surface,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.rowTitle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen == null || !navigator.mounted) return;
    // Someone's contact is theirs, not the user's: ask before passing it
    // on.
    final sure = await showAppConfirm(
      navigator.context,
      title: l10n.shareContactWarnTitle(
        state.person(chosen).name,
        state.person(chat).name,
      ),
      body: l10n.shareContactWarnBody(state.person(chat).name),
      confirmLabel: l10n.share,
    );
    if (!sure || !navigator.mounted) return;
    final sent = state.sendContact(chat, chosen);
    navigator.pop();
    if (!sent && navigator.mounted) {
      showAppToast(navigator.context, l10n.cardNotSent);
    }
  }

  /// True while the device is working out where it is, so that a second
  /// press does not start a second search.
  static bool _finding = false;

  /// Finds where the user is, says exactly what will be sent and to whom,
  /// and sends it only if they say yes. Nothing is found until they ask.
  Future<void> _location(BuildContext context) async {
    if (_finding) return;
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final chat = chatId;
    final channel = channelId;
    final Located found;
    _finding = true;
    try {
      // The search can take a while outdoors and longer inside. The user
      // can give up on it.
      var waiting = true;
      var gaveUp = false;
      unawaited(
        showAppSheet<void>(
          context,
          builder: (context) => _Finding(onCancel: Navigator.of(context).pop),
        ).then((_) {
          if (waiting) gaveUp = true;
          waiting = false;
        }),
      );
      found = await state.locate();
      if (waiting) {
        waiting = false;
        if (navigator.mounted) navigator.pop();
      }
      if (gaveUp || !navigator.mounted) return;
    } finally {
      _finding = false;
    }
    final place = found.place;
    if (place == null) {
      await _cannotLocate(navigator.context, state, found.why!);
      return;
    }
    // The warning says exactly what goes: the numbers, and how close.
    final where = place.accuracy > 0
        ? l10n.placeWithin(place.text, place.accuracy)
        : place.text;
    final sure = await showAppConfirm(
      navigator.context,
      title: l10n.shareLocationWarnTitle,
      body: chat != null
          ? l10n.shareLocationWarnBody(state.person(chat).name, where)
          : l10n.shareLocationWarnBodyChannel(where),
      confirmLabel: l10n.send,
    );
    if (!sure || !navigator.mounted) return;
    if (chat != null) {
      final sent = state.sendLocation(chat, place);
      navigator.pop();
      if (!sent && navigator.mounted) {
        showAppToast(navigator.context, l10n.locationNotSent);
      }
      return;
    }
    final (:sent, :refused) = state.sendChannelLocation(channel!, place);
    if (!sent) {
      showAppToast(
        navigator.context,
        refused == null ? l10n.locationNotSent : refusalText(l10n, refused),
      );
      return;
    }
    navigator.pop();
  }

  /// Says why there is no place to send, and where that can be changed.
  static Future<void> _cannotLocate(
    BuildContext context,
    AppState state,
    NoPlace why,
  ) async {
    final l10n = context.l10n;
    final device = state.isPc ? 'pc' : 'phone';
    if (why == NoPlace.unknown) {
      await showAppNotice(
        context,
        title: l10n.locationUnknownTitle,
        body: l10n.locationUnknownBody(device),
      );
      return;
    }
    final open = await showAppConfirm(
      context,
      title: why == NoPlace.denied
          ? l10n.locationDeniedTitle
          : l10n.locationOffTitle,
      body: why == NoPlace.denied
          ? l10n.locationDeniedBody(device)
          : l10n.locationOffBody(device),
      confirmLabel: l10n.openLocationSettings,
    );
    if (open) await state.openLocationSettings();
  }

  /// Takes a photo now and sends it where this sheet was opened from, as
  /// one chosen with Photo would go: with its location taken out if the
  /// user asked for that.
  Future<void> _camera(BuildContext context) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final chat = chatId;
    final channel = channelId;
    final path = await state.takePhoto(context);
    if (path == null || !context.mounted) return;
    if (channel != null) {
      if (!state.sendChannelFile(channel, path)) {
        showAppToast(context, l10n.channelFileNotSent);
        return;
      }
    } else if (chat != null && !state.sendFile(chat, path)) {
      showAppToast(context, l10n.fileNotSent);
      return;
    }
    navigator.pop();
  }

  /// Asks people into the space this channel is in: by a link to pass on,
  /// or a contact directly.
  void _invite(BuildContext context, Space space) {
    final navigator = Navigator.of(context);
    navigator.pop();
    showSpaceInvite(navigator.context, space);
  }

  /// A poll goes to the channel, or to the person, this was opened from.
  void _poll(BuildContext context) {
    final chat = chatId == savedMessagesId ? null : chatId;
    if (channelId == null && chat == null) {
      showNotBuiltYet(context);
      return;
    }
    final navigator = Navigator.of(context);
    navigator.pop();
    showNewPoll(navigator.context, channelId: channelId, chatId: chat);
  }

  /// Lets the user choose a file and offers it to the person in this chat.
  /// With [thenShow], goes on to the screen that shows it moving.
  Future<void> _sendFile(
    BuildContext context, {
    required bool thenShow,
    bool once = false,
  }) async {
    final l10n = context.l10n;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final chat = chatId;
    final channel = channelId;
    if (channel != null && state.canPickFiles) {
      final path = await state.pickFile();
      if (path == null || !context.mounted) return;
      if (state.cannotCleanPhoto(path)) {
        final sure = await showAppConfirm(
          context,
          title: l10n.cannotCleanTitle,
          body: l10n.cannotCleanBody,
          confirmLabel: l10n.sendAsItIs,
        );
        if (!sure || !context.mounted) return;
      }
      // A video goes with how long it runs, as this device reads it, so
      // members see that before they fetch it.
      final seconds = DirectFile.isVideoName(path)
          ? await probeVideoSeconds(path)
          : 0;
      if (!context.mounted) return;
      if (!state.sendChannelFile(channel, path, seconds: seconds)) {
        showAppToast(context, l10n.channelFileNotSent);
        return;
      }
      navigator.pop();
      return;
    }
    if (chat != null && chat != savedMessagesId && state.canPickFiles) {
      final path = await state.pickFile();
      if (path == null || !context.mounted) return;
      if (once && !DirectFile.isPictureName(path)) {
        showAppToast(context, l10n.viewOnceNotAPicture);
        return;
      }
      // The user asked for locations to be removed. If this picture is a
      // kind that cannot be cleaned, they are told before it goes.
      if (state.cannotCleanPhoto(path)) {
        final sure = await showAppConfirm(
          context,
          title: l10n.cannotCleanTitle,
          body: l10n.cannotCleanBody,
          confirmLabel: l10n.sendAsItIs,
        );
        if (!sure || !context.mounted) return;
      }
      if (!state.sendFile(chat, path, once: once)) {
        showAppToast(context, l10n.fileNotSent);
        return;
      }
    } else if (state.transfer == null) {
      // Files in channels, and on a device with no file chooser, are not
      // built.
      showNotBuiltYet(context);
      return;
    }
    navigator.pop();
    if (thenShow && state.transfer != null && navigator.mounted) {
      Go.fileTransfer(navigator.context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    // Only what can really be done from here is offered. Files go to a
    // person; a poll goes to a channel.
    final chat = chatId != null && chatId != savedMessagesId;
    final inChannel = channelId != null;
    // The space this channel is in, where members talk. A public
    // channel's feed shows only the owner's posts, so it has none: a place
    // is not posted there, and its followers are not invited from it.
    final groupSpace = inChannel
        ? state.spaces
              .where(
                (space) =>
                    !space.isBroadcast &&
                    space.channels.values.any(
                      (group) => group.any((c) => c.id == channelId),
                    ),
              )
              .firstOrNull
        : null;
    final inGroupChannel = groupSpace != null;
    final files =
        chat ||
        (inChannel && state.canPickFiles) ||
        state.works(Extra.filesInChannels);
    void stub() => showNotBuiltYet(context);
    final options = <(AppIconData, String, VoidCallback)>[
      // A photo taken now, where the device has a camera to take it.
      if (state.canTakePhoto && (chat || inChannel))
        (AppIcons.camera, l10n.shareCamera, () => _camera(context)),
      if (files)
        (
          AppIcons.photo,
          l10n.sharePhoto,
          () => _sendFile(context, thenShow: false),
        ),
      if (files && state.works(Extra.videos))
        (
          AppIcons.video,
          l10n.shareVideo,
          () => _sendFile(context, thenShow: false),
        ),
      if (files)
        (
          AppIcons.file,
          l10n.shareFile,
          () => _sendFile(context, thenShow: false),
        ),
      if (((chat || inChannel) && state.canRecordVoice) ||
          state.works(Extra.voiceInChannels))
        (AppIcons.mic, l10n.shareVoice, () => _voice(context)),
      if (channelId != null || chat || state.works(Extra.pollsInChats))
        (AppIcons.poll, l10n.sharePoll, () => _poll(context)),
      // A contact is passed on to a person. In a channel there is nobody
      // in particular to pass one to.
      if (state.works(Extra.shareContact) &&
          (chat || state.works(Extra.filesInChannels)))
        (
          AppIcons.person,
          l10n.shareContact,
          chat && state.canEditName ? () => _contact(context) : stub,
        ),
      if (state.works(Extra.shareLocation) && (chat || inGroupChannel))
        (AppIcons.location, l10n.shareLocation, () => _location(context)),
      // A picture to be seen once goes to a person.
      if (state.works(Extra.viewOnce) &&
          (chat || state.works(Extra.filesInChannels)))
        (
          AppIcons.timer,
          l10n.shareViewOnce,
          chat && state.canPickFiles
              ? () => _sendFile(context, thenShow: false, once: true)
              : stub,
        ),
      if (state.works(Extra.codeScanning))
        (AppIcons.qr, l10n.shareCameraCode, stub),
      // Sharing the space itself, with someone not in it yet.
      if (groupSpace != null)
        (AppIcons.personAdd, l10n.invite, () => _invite(context, groupSpace)),
    ];
    final columns = _columns(options.length);
    final bigFileRadius = BorderRadius.circular(AppRadius.card);
    final bigFileNear =
        chatId == null ||
        state.person(chatId!).link.kind != LinkKind.outOfRange;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.shareTitle,
                    style: AppText.base.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            AppIconButton(
              icon: AppIcons.close,
              label: l10n.close,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 8.0;
            final width = (box.maxWidth - gap * (columns - 1)) / columns;
            return Column(
              children: [
                for (var row = 0; row < options.length; row += columns) ...[
                  if (row > 0) const SizedBox(height: 18),
                  // A short last row sits in the middle, under the rest.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, option) in options.indexed)
                        if (i >= row && i < row + columns) ...[
                          if (i > row) const SizedBox(width: gap),
                          SizedBox(
                            width: width,
                            child: _Option(
                              icon: option.$1,
                              label: option.$2,
                              onTap: option.$3,
                            ),
                          ),
                        ],
                    ],
                  ),
                ],
              ],
            );
          },
        ),
        // A big file at Wi-Fi speed goes to a person. In a channel there
        // is nobody in particular to send it to.
        if (files && !inChannel) const SizedBox(height: 16),
        if (files && !inChannel)
          // Big files go straight to the person, so only while they are
          // near. Out of range, the option is greyed and says why.
          Opacity(
            opacity: bigFileNear ? 1 : 0.5,
            child: Pressable(
              onTap: bigFileNear
                  ? () => _sendFile(context, thenShow: true)
                  : null,
              focusRadius: bigFileRadius,
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: bigFileRadius,
                ),
                child: Row(
                  children: [
                    const AppIcon(
                      AppIcons.wifi,
                      size: 24,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.sendBigFile, style: AppText.strong),
                          Text(
                            !bigFileNear
                                ? l10n.bigFileNeedsRange(
                                    state.person(chatId!).name,
                                  )
                                : state.hasFastLink
                                ? l10n.sendBigFileDetail
                                : l10n.sendBigFileDetailBluetooth,
                            style: AppText.detail,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const AppIcon(
                      AppIcons.chevronRight,
                      size: 18,
                      color: AppColors.text2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        // The switch is only shown where photos really are stripped: where
        // a file can be sent at all.
        if (state.works(Extra.stripPhotoLocation) && files)
          const SizedBox(height: 16),
        if (state.works(Extra.stripPhotoLocation) && files)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(l10n.removeLocationFromPhotos),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AppSwitch(
                    value: state.removeLocationFromPhotos,
                    label: l10n.removeLocationFromPhotos,
                    onChanged: (on) => state.removeLocationFromPhotos = on,
                  ),
                ],
              ),
            ),
          ),
        // Nothing is taken out of a video, so nobody is left thinking it
        // is.
        if (state.works(Extra.stripPhotoLocation) &&
            files &&
            state.works(Extra.videos) &&
            state.removeLocationFromPhotos)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text(l10n.videosSentAsTheyAre, style: AppText.detail),
          ),
      ],
    );
  }
}

/// How many options go in a row: four if that fills every row, else three
/// or five if one of those does. Otherwise four, and the last row is
/// centred under the others.
int _columns(int count) {
  for (final columns in const [4, 3, 5]) {
    if (count % columns == 0) return columns;
  }
  return 4;
}

/// Shown while the device works out where it is.
class _Finding extends StatelessWidget {
  const _Finding({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const AppIcon(
                AppIcons.location,
                size: 24,
                color: AppColors.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l10n.findingLocation, style: AppText.rowTitle),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(label: l10n.cancel, onTap: onCancel),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.label, required this.onTap});

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.raised,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: AppIcon(icon, size: 24, color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.base.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
