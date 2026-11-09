import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../calls/call_engine.dart';
import '../calls/call_icons.dart';
import '../calls/screen_share.dart';
import '../calls/screen_view.dart';
import '../data/app_state.dart';
import '../data/models.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../widgets/avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';
import 'call_screen.dart';

enum _VoiceState {
  speaking,
  listening,
  muted,
  ownerMuted,
  soundOff,
  ownerDeaf,
  noWifi,
  joining,
}

/// 11 Voice room. Who is in the room, the call key everyone should see, and
/// the call controls.
///
/// Opening it goes into the room, muted. Going back leaves the user in the
/// room, with a bar across the top to come back; the red button leaves.
/// Sound goes only over Wi-Fi: someone in the room reached only over
/// Bluetooth is shown as having no Wi-Fi link.
class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({
    super.key,
    required this.spaceId,
    required this.channelId,
  });

  final String spaceId;
  final String channelId;

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  // Where the device has no calls (the design kit's sample world), the
  // user is shown joining muted.
  bool _muted = true;

  /// Whose shared screen is shown, where several share at once, and whose
  /// fills the window.
  String? _shown;
  String? _big;

  @override
  void initState() {
    super.initState();
    // Said after the frame: the bar above every screen listens, and must
    // not be changed while screens are being built or taken down.
    final room = widget.channelId;
    scheduleMicrotask(() => openVoiceRoom.value = room);
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  @override
  void dispose() {
    final room = widget.channelId;
    scheduleMicrotask(() {
      if (openVoiceRoom.value == room) openVoiceRoom.value = null;
    });
    super.dispose();
  }

  void _join() {
    if (!mounted) return;
    final state = AppScope.read(context);
    final calls = state.calls;
    if (calls == null) return;
    final problem = calls.joinRoom(widget.spaceId, widget.channelId);
    if (problem == null) return;
    final l10n = context.l10n;
    showAppToast(
      context,
      problem == CallProblem.busy ? l10n.callAlreadyIn : l10n.roomCannotJoin,
    );
    Navigator.of(context).maybePop();
  }

  void _leave(CallEngine? calls) {
    calls?.leaveRoom();
    Navigator.of(context).maybePop();
  }

  Future<void> _share(CallEngine calls) async {
    final l10n = context.l10n;
    final capture = calls.screen;
    final problem = calls.shareProblem;
    if (capture == null || problem != null) {
      final text = shareProblemText(l10n, problem);
      if (text != null) showAppToast(context, text);
      return;
    }
    final sources = await capture.sources();
    if (!mounted) return;
    ScreenSource? source;
    if (capture.systemPicks) {
      source = sources.firstOrNull;
    } else if (sources.isEmpty) {
      showAppToast(context, l10n.screenShareNothing);
      return;
    } else {
      source = await showAppSheet<ScreenSource>(
        context,
        builder: (context) => ScreenPicker(
          sources: sources,
          onPick: (source) => Navigator.of(context).pop(source),
        ),
      );
    }
    if (source == null || !mounted) return;
    final text = shareProblemText(
      l10n,
      await calls.startSharing(source, notice: shareNotice(l10n)),
    );
    if (text != null && mounted) showAppToast(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final space = state.space(widget.spaceId);
    final channel = state.channel(widget.spaceId, widget.channelId);
    final calls = state.calls;
    final room = calls?.room;
    final here =
        room != null &&
        room.space == widget.spaceId &&
        room.channel == widget.channelId;
    final runs = space.role != SpaceRole.member;
    final sharing = here ? calls!.sharing : null;
    final screens = here ? calls!.roomScreens : const <SharedScreen>[];
    final shown =
        screens.where((s) => s.from == _shown).firstOrNull ??
        screens.firstOrNull;
    final big = screens.where((s) => s.from == _big).firstOrNull;
    if (big != null) {
      return ScreenViewer(
        screen: big,
        name: state.person(big.from).name,
        onClose: () => setState(() => _big = null),
      );
    }

    final List<Widget> tiles;
    final List<String> words;
    if (calls == null) {
      // No calls on this device: the room as the space describes it.
      tiles = [
        for (final id in channel.talkerIds)
          _Tile(
            tone: state.person(id).tone,
            initial: state.person(id).initial,
            name: state.person(id).name,
            state: id == channel.speakingId
                ? _VoiceState.speaking
                : channel.mutedIds.contains(id)
                ? _VoiceState.muted
                : _VoiceState.listening,
          ),
        _Tile(
          tone: state.myTone,
          initial: state.profileInitial,
          name: l10n.you,
          state: _muted ? _VoiceState.muted : _VoiceState.listening,
        ),
      ];
      words = state.callWords(widget.channelId) ?? const [];
    } else {
      tiles = [
        for (final person in calls.roomPeople(widget.spaceId, widget.channelId))
          _Tile(
            tone: state.person(person.key).tone,
            initial: state.person(person.key).initial,
            photo: state.person(person.key).photo,
            name: state.person(person.key).name,
            state: _stateOf(calls, person),
            sharing: person.screen,
            // The core refuses anything aimed at the owner, or by an
            // admin at another admin, and the user is told.
            onTap: runs ? () => _manage(state, person) : null,
          ),
        _Tile(
          tone: state.myTone,
          initial: state.profileInitial,
          name: l10n.you,
          state: !here || room.asking
              ? _VoiceState.joining
              : room.ownerDeaf
              ? _VoiceState.ownerDeaf
              : room.ownerMuted
              ? _VoiceState.ownerMuted
              : room.muted
              ? _VoiceState.muted
              : calls.speaking('me')
              ? _VoiceState.speaking
              : room.deaf
              ? _VoiceState.soundOff
              : _VoiceState.listening,
          sharing: sharing != null,
        ),
      ];
      words = here ? room.words : const [];
    }

    final muted = calls == null ? _muted : (room?.muted ?? true);
    final deaf = room?.deaf ?? false;

    return AppScreen(
      header: AppTopBar(
        titleIcon: AppIcons.speaker,
        title: channel.name,
        subtitle: l10n.voiceRoomSubtitle(space.name),
        actions: [
          AppIconButton(
            icon: AppIcons.personAdd,
            label: l10n.inviteToRoom,
            onTap: () => showNotBuiltYet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        children: [
          if (sharing != null) ...[
            SharingBar(sharing: sharing, onStop: calls!.stopSharing),
            const SizedBox(height: 12),
          ],
          if (shown != null) ...[
            if (screens.length > 1) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final screen in screens)
                    AppButton(
                      label: state.person(screen.from).name,
                      icon: CallIcons.screen,
                      height: 44,
                      horizontalPadding: 14,
                      kind: identical(screen, shown)
                          ? AppButtonKind.primary
                          : AppButtonKind.secondary,
                      onTap: () => setState(() => _shown = screen.from),
                    ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: AspectRatio(
                aspectRatio: shown.width / shown.height,
                child: SharedScreenView(
                  screen: shown,
                  name: state.person(shown.from).name,
                  onEnlarge: () => setState(() => _big = shown.from),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          // Two to a row on a phone, more on a wide window, so the
          // tiles stay about the size they were drawn at.
          LayoutBuilder(
            builder: (context, box) {
              final across = (box.maxWidth / 220).floor().clamp(2, 6);
              return Column(
                children: [
                  for (var row = 0; row < tiles.length; row += across) ...[
                    if (row > 0) const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var i = row; i < row + across; i++) ...[
                          if (i > row) const SizedBox(width: 12),
                          Expanded(
                            child: i < tiles.length
                                ? tiles[i]
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (words.isNotEmpty)
            CallKeyCard(words: words, note: l10n.callKeyNote)
          else if (calls != null)
            Text(l10n.roomJoining, style: AppText.detail),
          if (calls != null && here && sharing == null && calls.shareEnded) ...[
            const SizedBox(height: 10),
            Text(
              l10n.screenShareEnded,
              style: AppText.detail.copyWith(color: AppColors.amber),
            ),
          ],
          if (calls != null && here && room.micMissing) ...[
            const SizedBox(height: 10),
            Text(
              l10n.callMicMissing,
              style: AppText.detail.copyWith(color: AppColors.amber),
            ),
          ],
          if (calls != null &&
              here &&
              calls.roomPeople(widget.spaceId, widget.channelId).isEmpty &&
              !room.asking) ...[
            const SizedBox(height: 10),
            Text(l10n.roomEmpty, style: AppText.detail),
          ],
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 30),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CallControl(
              icon: muted ? AppIcons.micOff : AppIcons.mic,
              label: muted ? l10n.unmuteMicrophone : l10n.muteMicrophone,
              onTap: () {
                if (calls == null) {
                  setState(() => _muted = !_muted);
                } else if (room != null && room.ownerMuted) {
                  showAppToast(context, l10n.roomYouOwnerMuted);
                } else {
                  calls.setMuted(!muted);
                }
              },
            ),
            CallControl(
              icon: deaf ? CallIcons.soundOff : AppIcons.speaker,
              label: deaf ? l10n.soundOn : l10n.soundOff,
              selected: deaf,
              onTap: calls == null
                  ? () => showNotBuiltYet(context)
                  : () => calls.setDeaf(!deaf),
            ),
            CallControl(
              icon: AppIcons.video,
              label: l10n.turnCameraOn,
              onTap: () => showNotBuiltYet(context),
            ),
            if (calls != null && calls.canShareScreen)
              ShareControl(
                sharing: sharing != null,
                needsWifi: here && calls.shareProblem == ShareProblem.needsWifi,
                onTap: !here || room.asking
                    ? null
                    : sharing != null
                    ? calls.stopSharing
                    : () => _share(calls),
              ),
            CallControl(
              icon: AppIcons.close,
              label: l10n.leaveTheRoom,
              color: AppColors.redInk,
              background: AppColors.red,
              onTap: () => _leave(calls),
            ),
          ],
        ),
      ),
    );
  }

  _VoiceState _stateOf(CallEngine calls, RoomPerson person) {
    if (person.ownerDeaf) return _VoiceState.ownerDeaf;
    if (person.ownerMuted) return _VoiceState.ownerMuted;
    if (calls.fastLinkTo(person.key) == null) return _VoiceState.noWifi;
    if (calls.speaking(person.key) && !person.muted) {
      return _VoiceState.speaking;
    }
    if (person.muted) return _VoiceState.muted;
    if (person.deaf) return _VoiceState.soundOff;
    return _VoiceState.listening;
  }

  /// Whoever runs the space mutes or deafens someone in its voice rooms.
  /// The word is signed and reaches every member's device.
  Future<void> _manage(AppState state, RoomPerson person) async {
    final l10n = context.l10n;
    final name = state.person(person.key).name;
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: person.ownerMuted
                ? l10n.roomUnmuteFor(name)
                : l10n.roomMuteFor(name),
            icon: person.ownerMuted ? AppIcons.mic : AppIcons.micOff,
            onTap: () => Navigator.of(context).pop('mute'),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: person.ownerDeaf
                ? l10n.roomUndeafen(name)
                : l10n.roomDeafen(name),
            icon: person.ownerDeaf ? AppIcons.speaker : CallIcons.soundOff,
            onTap: () => Navigator.of(context).pop('deafen'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final done = state.setVoiceRule(
      widget.spaceId,
      person.key,
      mute: choice == 'mute' ? !person.ownerMuted : person.ownerMuted,
      deafen: choice == 'deafen' ? !person.ownerDeaf : person.ownerDeaf,
    );
    if (!done && mounted) showAppToast(context, l10n.roomRuleNotSet);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tone,
    required this.initial,
    required this.name,
    required this.state,
    this.photo,
    this.onTap,
    this.sharing = false,
  });

  final AvatarTone tone;
  final String initial;
  final String name;
  final _VoiceState state;
  final Uint8List? photo;

  /// Is sharing their screen with the room.
  final bool sharing;

  /// For whoever runs the space: mute or deafen this person.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final speaking = state == _VoiceState.speaking;
    final (AppIconData? icon, String label) = switch (state) {
      _VoiceState.speaking => (null, l10n.speaking),
      _VoiceState.listening => (null, l10n.listening),
      _VoiceState.muted => (AppIcons.micOff, l10n.muted),
      _VoiceState.ownerMuted => (AppIcons.micOff, l10n.roomOwnerMuted),
      _VoiceState.soundOff => (CallIcons.soundOff, l10n.roomSoundOff),
      _VoiceState.ownerDeaf => (CallIcons.soundOff, l10n.roomOwnerDeafened),
      _VoiceState.noWifi => (AppIcons.wifi, l10n.roomNoWifi),
      _VoiceState.joining => (null, l10n.roomJoining),
    };
    final tile = Container(
      constraints: const BoxConstraints(minHeight: 156),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.hero),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Avatar(
            tone: tone,
            label: initial,
            photo: photo,
            size: 64,
            surround: AppColors.surface,
            ringColor: speaking ? AppColors.green : null,
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.strong,
          ),
          const SizedBox(height: 2),
          if (speaking)
            Text(
              label,
              style: AppText.base.copyWith(
                color: AppColors.green,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  AppIcon(icon, size: 14, color: AppColors.text2),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.detail,
                  ),
                ),
              ],
            ),
          if (sharing) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(
                  CallIcons.screen,
                  size: 14,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.screenShareSharing,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.detail.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      child: onTap == null
          ? tile
          : Pressable(
              onTap: onTap,
              focusRadius: BorderRadius.circular(AppRadius.hero),
              child: tile,
            ),
    );
  }
}
