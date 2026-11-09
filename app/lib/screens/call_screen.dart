import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import '../calls/call_engine.dart';
import '../calls/call_icons.dart';
import '../calls/screen_share.dart';
import '../calls/screen_view.dart';
import '../data/app_state.dart';
import '../design/app_icon.dart';
import '../design/app_icons.g.dart';
import '../design/tokens.dart';
import '../l10n/l10n.dart';
import '../routes.dart';
import '../widgets/avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/feedback.dart';
import '../widgets/pressable.dart';
import '../widgets/scaffold.dart';

/// The navigator the app's screens are on. Calls are drawn above it, so
/// they reach the screens through this.
final appNavigator = GlobalKey<NavigatorState>();

/// The voice room whose screen is open, if one is. Its bar is not shown
/// over it.
final openVoiceRoom = ValueNotifier<String?>(null);

/// Wraps every screen. A call that is ringing, going on or just ended is
/// drawn over everything. Once the user goes back to the app during a
/// call, or leaves a voice room's screen without leaving the room, a bar
/// across the top takes them back to it.
class CallFrame extends StatefulWidget {
  const CallFrame({super.key, required this.child});

  final Widget child;

  @override
  State<CallFrame> createState() => _CallFrameState();
}

class _CallFrameState extends State<CallFrame> {
  /// The call the user put to one side, by id.
  String? _aside;
  Timer? _ticking;

  /// Sharing stops when the app's window closes.
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onDetach: _stopSharing,
      onExitRequested: () async {
        _stopSharing();
        return AppExitResponse.exit;
      },
    );
  }

  void _stopSharing() {
    if (!mounted) return;
    AppScope.read(context).calls?.stopSharing();
  }

  @override
  void dispose() {
    _life.dispose();
    _ticking?.cancel();
    super.dispose();
  }

  /// Keeps the time on screen moving while a call is live.
  void _tick(bool live) {
    if (live && _ticking == null) {
      _ticking = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!live) {
      _ticking?.cancel();
      _ticking = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final calls = state.calls;
    final call = calls?.call;
    final room = calls?.room;
    _tick(call?.phase == CallPhase.live);
    final full =
        call != null &&
        call.showable &&
        (call.id != _aside ||
            call.phase == CallPhase.incoming ||
            call.phase == CallPhase.ended);
    return ValueListenableBuilder<String?>(
      valueListenable: openVoiceRoom,
      builder: (context, open, _) {
        final Widget? bar = full
            ? null
            : call != null && call.showable
            ? _Bar(
                label: _barLabel(context, state, call),
                onTap: () => setState(() => _aside = null),
              )
            : room != null && open != room.channel
            ? _Bar(
                label: context.l10n.callBarRoom(
                  state.channel(room.space, room.channel).name,
                ),
                onTap: () {
                  final at = appNavigator.currentContext;
                  if (at != null) Go.voiceRoom(at, room.space, room.channel);
                },
              )
            : null;
        // While the user is sharing their screen and its call or room is
        // out of sight, a strip says so, with a button to stop.
        final sharing = calls?.sharing;
        final Widget? strip =
            sharing != null && !full && !(room != null && open == room.channel)
            ? _ShareStrip(sharing: sharing, onStop: calls!.stopSharing)
            : null;
        return Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                ?strip,
                if (bar != null)
                  MediaQuery.removePadding(
                    context: context,
                    removeTop: strip != null,
                    child: bar,
                  ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: bar != null || strip != null,
                    child: ExcludeSemantics(
                      excluding: full,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
            if (full)
              Positioned.fill(
                child: CallScreen(
                  call: call,
                  onAside: () => setState(() => _aside = call.id),
                ),
              ),
          ],
        );
      },
    );
  }

  String _barLabel(BuildContext context, AppState state, CallSession call) {
    final name = state.person(call.peer).name;
    final since = call.since;
    final text = context.l10n.callBarPerson(name);
    return since == null
        ? text
        : '$text · ${_clock(DateTime.now().difference(since))}';
  }
}

String _clock(Duration time) {
  final minutes = time.inMinutes;
  final seconds = time.inSeconds % 60;
  final hours = time.inHours;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes % 60)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

class _ShareStrip extends StatelessWidget {
  const _ShareStrip({required this.sharing, required this.onStop});

  final ScreenSource sharing;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: SharingBar(sharing: sharing, onStop: onStop),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.greenSoft,
      child: SafeArea(
        bottom: false,
        child: Pressable(
          onTap: onTap,
          semanticLabel: '$label. ${context.l10n.callReturn}',
          focusRadius: BorderRadius.zero,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const AppIcon(AppIcons.phone, size: 16, color: AppColors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.base.copyWith(
                      color: AppColors.green,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const AppIcon(
                  AppIcons.chevronRight,
                  size: 16,
                  color: AppColors.green,
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A call with one person: ringing, going on, or just over.
///
/// Calls are drawn above the app's screens, where no sheet or toast can
/// open, so choosing what to share and seeing a shared screen bigger
/// happen inside this screen.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.call, required this.onAside});

  final CallSession call;

  /// Goes back to the app with the call still going.
  final VoidCallback onAside;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  /// What the user may share, while they choose.
  List<ScreenSource>? _picking;

  /// Their shared screen fills the window.
  bool _big = false;

  /// Why sharing did not start, shown for a few seconds.
  String? _note;
  Timer? _noteTimer;

  @override
  void dispose() {
    _noteTimer?.cancel();
    super.dispose();
  }

  void _say(String? note) {
    if (note == null || !mounted) return;
    _noteTimer?.cancel();
    setState(() => _note = note);
    _noteTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _note = null);
    });
  }

  Future<void> _share(CallEngine calls) async {
    final l10n = context.l10n;
    final capture = calls.screen;
    final problem = calls.shareProblem;
    if (capture == null || problem != null) {
      _say(shareProblemText(l10n, problem));
      return;
    }
    final sources = await capture.sources();
    if (!mounted) return;
    if (capture.systemPicks && sources.isNotEmpty) {
      await _start(calls, sources.first);
    } else if (sources.isEmpty) {
      _say(l10n.screenShareNothing);
    } else {
      setState(() => _picking = sources);
    }
  }

  Future<void> _start(CallEngine calls, ScreenSource source) async {
    final l10n = context.l10n;
    setState(() => _picking = null);
    _say(
      shareProblemText(
        l10n,
        await calls.startSharing(source, notice: shareNotice(l10n)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final onAside = widget.onAside;
    final l10n = context.l10n;
    final state = AppScope.of(context);
    final calls = state.calls!;
    final person = state.person(call.peer);
    final live = call.phase == CallPhase.live;
    final shared = live ? calls.screenOf(call.peer) : null;
    if (_big && shared != null) {
      return ScreenViewer(
        screen: shared,
        name: person.name,
        onClose: () => setState(() => _big = false),
      );
    }
    final sharing = live ? calls.sharing : null;
    final needsWifi = calls.shareProblem == ShareProblem.needsWifi;
    // A shared screen takes the space their camera would.
    final picture = shared == null && call.video && call.theirCamera
        ? call.picture
        : null;

    final status = switch (call.phase) {
      CallPhase.calling ||
      CallPhase.ringing when !call.wifi => l10n.callSettingUpWifi,
      CallPhase.calling => l10n.callCalling,
      CallPhase.ringing => l10n.callRinging,
      CallPhase.incoming => call.video ? l10n.videoCall : l10n.voiceCall,
      CallPhase.live => _clock(DateTime.now().difference(call.since!)),
      CallPhase.ended => switch (call.end) {
        CallEnd.declined => l10n.callDeclined(person.name),
        CallEnd.busy => l10n.callBusy(person.name),
        CallEnd.unanswered => l10n.callNoAnswer,
        CallEnd.noWifi => l10n.callNeedsWifi(person.name),
        CallEnd.lost => l10n.callLost(person.name),
        CallEnd.failed => l10n.callFailed,
        _ => l10n.callEnded,
      },
    };

    final notices = [
      if (live && call.micMissing) l10n.callMicMissing,
      if (live && !call.wifi) l10n.callReconnecting,
      if (live && call.theyMuted) l10n.callTheyMuted(person.name),
      if (live && call.video && !call.theirCamera)
        l10n.callTheirCameraOff(person.name),
      if (live && sharing == null && calls.shareEnded) l10n.screenShareEnded,
      ?_note,
    ];

    final controls = switch (call.phase) {
      CallPhase.incoming => [
        CallControl(
          icon: AppIcons.close,
          label: l10n.decline,
          color: AppColors.redInk,
          background: AppColors.red,
          onTap: calls.decline,
        ),
        CallControl(
          icon: call.video ? AppIcons.video : AppIcons.phone,
          label: l10n.callAnswer,
          color: AppColors.greenInk,
          background: AppColors.green,
          onTap: calls.answer,
        ),
      ],
      CallPhase.ended => <Widget>[],
      _ => [
        CallControl(
          icon: call.muted ? AppIcons.micOff : AppIcons.mic,
          label: call.muted ? l10n.unmuteMicrophone : l10n.muteMicrophone,
          selected: call.muted,
          onTap: live ? () => calls.setMuted(!call.muted) : null,
        ),
        if (calls.audio.hasEarpiece)
          CallControl(
            icon: AppIcons.speaker,
            label: call.loudspeaker
                ? l10n.callLoudspeakerOff
                : l10n.callLoudspeakerOn,
            selected: call.loudspeaker,
            onTap: () => calls.setLoudspeaker(!call.loudspeaker),
          ),
        if (call.video && calls.canVideo)
          CallControl(
            icon: call.camera ? AppIcons.video : CallIcons.cameraOff,
            label: call.camera ? l10n.turnCameraOff : l10n.turnCameraOn,
            selected: !call.camera,
            onTap: live ? () => calls.setCamera(!call.camera) : null,
          ),
        if (calls.canShareScreen)
          ShareControl(
            sharing: sharing != null,
            needsWifi: live && needsWifi,
            onTap: !live
                ? null
                : sharing != null
                ? calls.stopSharing
                : () => _share(calls),
          ),
        CallControl(
          icon: AppIcons.close,
          label: l10n.callHangUp,
          color: AppColors.redInk,
          background: AppColors.red,
          onTap: calls.hangUp,
        ),
      ],
    };

    final content = AppScreen(
      header: SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 8),
            if (call.phase != CallPhase.incoming &&
                call.phase != CallPhase.ended)
              AppIconButton(
                icon: AppIcons.back,
                label: l10n.callMinimise,
                onTap: onAside,
              ),
          ],
        ),
      ),
      body: FillScroll(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          if (sharing != null) ...[
            const SizedBox(height: 4),
            SharingBar(sharing: sharing, onStop: calls.stopSharing),
          ],
          const SizedBox(height: 24),
          if (shared != null) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: AspectRatio(
                aspectRatio: shared.width / shared.height,
                child: SharedScreenView(
                  screen: shared,
                  name: person.name,
                  onEnlarge: () => setState(() => _big = true),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ] else if (picture == null) ...[
            Center(
              child: Avatar(
                tone: person.tone,
                label: person.initial,
                photo: person.photo,
                size: 112,
                fontSize: 40,
                ringColor: live && calls.speaking(call.peer)
                    ? AppColors.green
                    : null,
              ),
            ),
            const SizedBox(height: 18),
          ] else
            const SizedBox(height: 130),
          Semantics(
            header: true,
            child: Text(
              call.phase == CallPhase.incoming
                  ? l10n.callIsCalling(person.name)
                  : person.name,
              textAlign: TextAlign.center,
              style: AppText.screenTitle,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: AppText.detail14,
            ),
          ),
          if (live) ...[
            const SizedBox(height: 4),
            Text(
              l10n.callOverWifi,
              textAlign: TextAlign.center,
              style: AppText.footnote,
            ),
          ],
          const Spacer(),
          if (live && call.words.isNotEmpty) ...[
            const SizedBox(height: 20),
            CallKeyCard(words: call.words, note: l10n.callKeyNoteTwo),
          ],
          for (final notice in notices) ...[
            const SizedBox(height: 10),
            Text(
              notice,
              textAlign: TextAlign.center,
              style: AppText.detail.copyWith(color: AppColors.amber),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
      footer: controls.isEmpty
          ? const SizedBox(height: 40)
          : Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 30),
              child: Row(
                mainAxisAlignment: controls.length > 2
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.spaceEvenly,
                children: controls,
              ),
            ),
    );

    final picking = _picking;
    final Widget? picker = picking == null
        ? null
        : _InlineSheet(
            onClose: () => setState(() => _picking = null),
            child: ScreenPicker(
              sources: picking,
              onPick: (source) => _start(calls, source),
            ),
          );
    if (picture == null) {
      return picker == null
          ? content
          : Stack(fit: StackFit.expand, children: [content, picker]);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RotatedBox(
          quarterTurns: call.pictureTurns,
          child: Image.memory(
            picture,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            semanticLabel: person.name,
          ),
        ),
        // Darkens the picture under the words and buttons.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0x00000000), Color(0xCC000000)],
              stops: [0, 0.4, 1],
            ),
          ),
        ),
        ColoredBox(color: const Color(0x00000000), child: content),
        if (call.myPicture case final mine?)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 64,
            right: 16,
            width: 96,
            height: 128,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              // Shown as in a mirror, the way people expect to see
              // themselves. They are sent the right way round.
              child: Transform.flip(
                flipX: true,
                child: RotatedBox(
                  quarterTurns: call.myPictureTurns,
                  child: Image.memory(
                    mine,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ?picker,
      ],
    );
  }
}

/// A sheet drawn inside the call, which is above the app's screens.
class _InlineSheet extends StatelessWidget {
  const _InlineSheet({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: onClose,
          child: const ColoredBox(color: Color(0x4D000000)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.switchOff,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The round control that shares the screen, or stops sharing it. Where
/// only Bluetooth reaches the others it says Wi-Fi is needed, and is
/// dimmed; tapping it then says why.
class ShareControl extends StatelessWidget {
  const ShareControl({
    super.key,
    required this.sharing,
    required this.needsWifi,
    required this.onTap,
  });

  final bool sharing;
  final bool needsWifi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CallControl(
      icon: CallIcons.screen,
      label: sharing
          ? l10n.screenShareStop
          : needsWifi
          ? l10n.screenShareNeedsWifiShort
          : l10n.screenShare,
      selected: sharing,
      color: needsWifi && !sharing ? AppColors.text3 : AppColors.text,
      onTap: onTap,
    );
  }
}

/// What Android's notice says while the screen is shared.
ScreenNotice shareNotice(AppLocalizations l10n) => (
  title: l10n.screenShareNoticeTitle,
  text: l10n.screenShareNoticeText,
  stop: l10n.screenShareStop,
);

/// What to tell the user when sharing did not start, if anything.
String? shareProblemText(AppLocalizations l10n, ShareProblem? problem) =>
    switch (problem) {
      ShareProblem.needsWifi => l10n.screenShareNeedsWifi,
      ShareProblem.failed => l10n.screenShareFailed,
      _ => null,
    };

/// The card showing the call key words.
class CallKeyCard extends StatelessWidget {
  const CallKeyCard({super.key, required this.words, required this.note});

  final List<String> words;
  final String note;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIcon(
                AppIcons.verified,
                size: 15,
                color: AppColors.green,
              ),
              const SizedBox(width: 8),
              Text(context.l10n.callKey, style: AppText.sectionLabel),
            ],
          ),
          const SizedBox(height: 6),
          Text(words.join(' '), style: AppText.mono(16)),
          const SizedBox(height: 6),
          Text(note, style: AppText.detail),
        ],
      ),
    );
  }
}

/// One round call control.
class CallControl extends StatelessWidget {
  const CallControl({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.text,
    this.background = AppColors.raised,
    this.selected = false,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color background;

  /// Switched to its "off" state, such as muted.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: icon,
      label: label,
      size: 60,
      iconSize: 24,
      color: selected ? AppColors.bg : color,
      background: selected ? AppColors.text : background,
      round: true,
      onTap: onTap,
    );
  }
}

/// Calls a contact, or says why that cannot be done.
void startCall(BuildContext context, String personId, {bool video = false}) {
  final state = AppScope.read(context);
  final problem = state.calls?.start(personId, video: video);
  if (problem == null) return;
  final l10n = context.l10n;
  showAppToast(context, switch (problem) {
    CallProblem.notInRange => l10n.callNotInRange(state.person(personId).name),
    CallProblem.busy => l10n.callAlreadyIn,
    CallProblem.refused => l10n.callRefused,
  });
}
