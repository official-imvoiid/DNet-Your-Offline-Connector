import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/core_bridge.dart';
import '../radio/link_pump.dart';
import 'call_audio.dart';
import 'call_camera.dart';
import 'screen_share.dart';

/// How far a call between two people has got.
enum CallPhase {
  /// The user called. Nothing heard back yet, or Wi-Fi is being set up.
  calling,

  /// The user called and it is ringing there.
  ringing,

  /// Someone is calling the user.
  incoming,

  /// Answered. Sound is flowing.
  live,

  /// Over. Shown for a moment, then gone.
  ended,
}

/// Why a call ended, or never began.
enum CallEnd {
  /// One of the two hung up.
  hangup,

  /// The person called turned it down.
  declined,

  /// They were already in a call.
  busy,

  /// Nobody answered.
  unanswered,

  /// No Wi-Fi link could be set up between the two. Bluetooth alone is
  /// far too slow for live sound.
  noWifi,

  /// The link to them was lost during the call.
  lost,

  /// The call could not be set up safely.
  failed,
}

/// Why a call or a voice room could not be started.
enum CallProblem {
  /// The user is already in a call or a room.
  busy,

  /// The person is not in range.
  notInRange,

  /// The core refused: not a contact, not a voice room, or deafened by
  /// whoever runs the space.
  refused,
}

/// Why the user's screen could not be shared.
enum ShareProblem {
  /// This device cannot capture its screen.
  unsupported,

  /// There is no call going on, or the user is not let into the room yet.
  notLive,

  /// Only Bluetooth reaches them: far too slow for a screen.
  needsWifi,

  /// Capture could not start: on Android, nearly always because the user
  /// said no.
  failed,
}

/// How long the engine waits for each thing. Tests make them short.
@immutable
class CallTimes {
  const CallTimes({
    this.wifiWait = const Duration(seconds: 25),
    this.ringFor = const Duration(seconds: 45),
    this.lostAfter = const Duration(seconds: 12),
    this.endedFor = const Duration(milliseconds: 2500),
    this.askWait = const Duration(seconds: 3),
    this.roomEvery = const Duration(seconds: 4),
    this.watchEvery = const Duration(milliseconds: 250),
    this.shareEvery = const Duration(milliseconds: 100),
  });

  /// How long to wait for a Wi-Fi link before giving up on a call.
  final Duration wifiWait;

  /// How long a call rings before it counts as unanswered.
  final Duration ringFor;

  /// How long a live call may go without a Wi-Fi link before it ends.
  final Duration lostAfter;

  /// How long an ended call stays on screen.
  final Duration endedFor;

  /// How long to wait for someone in a voice room to let the user in
  /// before opening it afresh.
  final Duration askWait;

  /// How often the user says they are still in a voice room.
  final Duration roomEvery;
  final Duration watchEvery;

  /// How often pieces of the user's shared screen are collected and sent.
  final Duration shareEvery;
}

/// A call between the user and one contact.
class CallSession {
  CallSession._({
    required this.id,
    required this.peer,
    required this.mine,
    required this.video,
    required this.phase,
    required this.began,
  });

  final String id;

  /// The other person's signing key.
  final String peer;

  /// The user started it.
  final bool mine;
  final bool video;
  CallPhase phase;
  final DateTime began;

  /// Why it ended, once it has.
  CallEnd? end;

  /// The call key words, once answered. Both sides see the same four.
  List<String> words = const [];

  /// When it was answered.
  DateTime? since;

  bool muted = false;
  bool loudspeaker = false;
  bool camera = false;
  bool theyMuted = false;
  bool theirCamera = false;

  /// They say they are sharing their screen.
  bool theirScreen = false;

  /// Whether a Wi-Fi link reaches them right now. Sound goes no other way.
  bool wifi = false;

  /// The microphone could not be started: the user hears but is not
  /// heard.
  bool micMissing = false;

  /// Their latest picture, in a video call, and how many quarter turns
  /// clockwise it needs to stand upright.
  Uint8List? picture;
  int pictureTurns = 0;

  /// The user's own latest picture, and its turns.
  Uint8List? myPicture;
  int myPictureTurns = 0;

  DateTime? _rang;
  DateTime? _lostSince;

  /// Whether an incoming call should be shown yet: only once Wi-Fi is up,
  /// since without it the call could not be answered.
  bool get showable => phase != CallPhase.incoming || wifi;
}

/// Someone in a voice room.
@immutable
class RoomPerson {
  const RoomPerson({
    required this.key,
    this.muted = false,
    this.deaf = false,
    this.ownerMuted = false,
    this.ownerDeaf = false,
    this.camera = false,
    this.screen = false,
  });

  final String key;
  final bool muted;
  final bool deaf;

  /// Whoever runs the space muted, or deafened, them here.
  final bool ownerMuted;
  final bool ownerDeaf;
  final bool camera;

  /// Is sharing their screen with the room.
  final bool screen;
}

/// The voice room the user is in.
class RoomSession {
  RoomSession._(this.space, this.channel);

  final String space;
  final String channel;

  /// The room's number, once the user is let in.
  String? call;

  /// The call key words everyone inside should see.
  List<String> words = const [];

  /// The user joins muted.
  bool muted = true;

  /// The user has the sound off.
  bool deaf = false;
  bool micMissing = false;

  /// Whoever runs the space muted, or deafened, the user here.
  bool ownerMuted = false;
  bool ownerDeaf = false;

  DateTime? _askedAt;
  DateTime _toldAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Still waiting to be let in.
  bool get asking => call == null;
}

/// Calls between two people and voice rooms in spaces: what is said to set
/// them up (sealed by the core), and the sound itself, which goes only
/// over a Wi-Fi link.
///
/// The engine holds no keys. It asks the core to seal each block of sound
/// and to open each that arrives, and hands the frames to the radio.
class CallEngine extends ChangeNotifier {
  CallEngine({
    required this._bridge,
    required this._pump,
    required this.audio,
    this.camera,
    this.screen,
    required this.fastLinkTo,
    required this.inRange,
    required this.wantFast,
    this.times = const CallTimes(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _pump.onMedia = _mediaIn;
    _pump.onEvents(_onEvents);
  }

  final CoreBridge _bridge;
  final LinkPump _pump;
  final DateTime Function() _clock;
  final CallAudio audio;
  final CallCamera? camera;

  /// Captures the user's screen, where this device can.
  final ScreenCapture? screen;
  final CallTimes times;

  /// The fast link that reaches this person, if one does.
  final int? Function(String peer) fastLinkTo;
  final bool Function(String peer) inRange;

  /// Asks for a Wi-Fi link to be set up to someone in range.
  final void Function(String peer) wantFast;

  CallSession? _call;
  RoomSession? _room;
  List<Map<String, Object?>> _rooms = const [];

  /// The call going on, ringing, or just ended, if any.
  CallSession? get call => _call;

  /// The voice room the user is in, if any.
  RoomSession? get room => _room;

  /// Whether video calls can be made here.
  bool get canVideo => camera != null;

  /// Whether the user can share their screen here.
  bool get canShareScreen => screen != null;

  Timer? _watching;
  Timer? _mixing;
  Timer? _clearing;
  bool _mediaOn = false;

  // Talking to the core

  Map<String, Object?>? _ask(Map<String, Object?> request) {
    try {
      final reply = _bridge.call(request);
      return reply is Map<String, Object?> ? reply : const {};
    } on CoreException {
      return null;
    }
  }

  /// Asks the core, then sends whatever it wants sent.
  Map<String, Object?>? _do(Map<String, Object?> request) {
    final reply = _ask(request);
    if (reply != null) _pump.sendDeliveries(reply);
    return reply;
  }

  // Calls between two people

  /// Calls a contact. Null if it is on its way, or why not.
  CallProblem? start(String peer, {bool video = false}) {
    if (_call != null && _call!.phase != CallPhase.ended) {
      return CallProblem.busy;
    }
    if (_room != null) return CallProblem.busy;
    if (!inRange(peer)) return CallProblem.notInRange;
    final wantVideo = video && camera != null;
    final reply = _ask({'op': 'call_start', 'to': peer, 'video': wantVideo});
    if (reply == null) return CallProblem.refused;
    _clearing?.cancel();
    _call =
        CallSession._(
            id: reply['call']! as String,
            peer: peer,
            mine: true,
            video: wantVideo,
            phase: CallPhase.calling,
            began: _clock(),
          )
          ..camera = wantVideo
          ..theirCamera = wantVideo;
    // Sent once the call is known here: the answer to it may come at once.
    _pump.sendDeliveries(reply);
    _wifiCheck(_call!);
    _watch();
    notifyListeners();
    return null;
  }

  /// Answers the call that is ringing.
  void answer() {
    final call = _call;
    if (call == null || call.phase != CallPhase.incoming) return;
    final reply = _do({'op': 'call_answer', 'call': call.id});
    if (reply == null) {
      _finish(CallEnd.failed);
      return;
    }
    call
      ..words = _strings(reply['words'])
      ..phase = CallPhase.live
      ..since = _clock()
      ..camera = call.video && camera != null;
    _startMedia();
    notifyListeners();
  }

  /// Turns down the call that is ringing.
  void decline() {
    final call = _call;
    if (call == null || call.phase != CallPhase.incoming) return;
    _do({'op': 'call_end', 'call': call.id, 'reason': 'declined'});
    _finish(CallEnd.declined, show: false);
  }

  /// Hangs up, or stops calling.
  void hangUp() {
    final call = _call;
    if (call == null || call.phase == CallPhase.ended) return;
    _do({'op': 'call_end', 'call': call.id, 'reason': 'hangup'});
    _finish(CallEnd.hangup);
  }

  void setMuted(bool muted) {
    final call = _call;
    if (call != null && call.phase != CallPhase.ended) {
      call.muted = muted;
      _tell(call);
    }
    final room = _room;
    if (room != null) {
      room.muted = muted;
      _roomTick(force: true);
    }
    notifyListeners();
  }

  /// Turns the sound off, in a voice room: nothing is played and nothing
  /// need be sent to the user.
  void setDeaf(bool deaf) {
    final room = _room;
    if (room == null) return;
    room.deaf = deaf;
    if (deaf) _queues.clear();
    _roomTick(force: true);
    notifyListeners();
  }

  void setLoudspeaker(bool on) {
    final call = _call;
    if (call == null) return;
    call.loudspeaker = on;
    audio.loudspeaker(on);
    notifyListeners();
  }

  /// Turns the user's camera on or off in a video call.
  Future<void> setCamera(bool on) async {
    final call = _call;
    if (call == null || !call.video || camera == null) return;
    call.camera = on;
    if (!on) call.myPicture = null;
    _tell(call);
    if (call.phase == CallPhase.live) {
      if (on) {
        await _startCamera();
      } else {
        await camera?.stop();
      }
    }
    notifyListeners();
  }

  void _tell(CallSession call) {
    if (call.phase != CallPhase.live) return;
    _do({
      'op': 'call_tell',
      'call': call.id,
      'muted': call.muted,
      'camera': call.camera,
      'screen': _sharing != null,
    });
  }

  void _finish(CallEnd why, {bool show = true}) {
    final call = _call;
    if (call == null) return;
    call
      ..phase = CallPhase.ended
      ..end = why;
    // Nothing goes on being shared once the call is over: stopping the
    // media stops sharing too.
    if (_room == null) {
      _forgetScreens();
      _stopMedia();
    }
    _clearing?.cancel();
    if (show) {
      _clearing = Timer(times.endedFor, () {
        if (identical(_call, call)) {
          _call = null;
          notifyListeners();
        }
      });
    } else {
      _call = null;
    }
    notifyListeners();
  }

  /// Whether a Wi-Fi link to [peer] is wanted for a call or a room.
  bool needsFastLink(String peer) {
    final call = _call;
    if (call != null && call.peer == peer && call.phase != CallPhase.ended) {
      return true;
    }
    return _room != null && roomPeople().any((p) => p.key == peer);
  }

  /// Whether a call or a room is going on, so a Wi-Fi link set up for it
  /// must be kept.
  bool get busy =>
      _room != null || (_call != null && _call!.phase != CallPhase.ended);

  void _wifiCheck(CallSession call) {
    final wifi = fastLinkTo(call.peer) != null;
    if (wifi != call.wifi) {
      call.wifi = wifi;
      if (wifi && call.phase == CallPhase.ringing) call._rang ??= _clock();
    }
    if (!wifi && inRange(call.peer)) wantFast(call.peer);
  }

  // What the core reports

  void _onEvents(List<Map<String, Object?>> events) {
    var changed = false;
    for (final event in events) {
      final call = _call;
      final from = event['from'] as String?;
      final mine = call != null && event['call'] == call.id;
      switch (event['kind']) {
        case 'call_offer':
          final replaces = event['replaces'] as String?;
          final crossed =
              call != null &&
              replaces == call.id &&
              call.phase != CallPhase.ended;
          if (call != null && call.phase != CallPhase.ended && !crossed) break;
          _clearing?.cancel();
          _call = CallSession._(
            id: event['call']! as String,
            peer: from!,
            mine: false,
            // A device with no camera still sees theirs.
            video: event['video'] == true,
            phase: CallPhase.incoming,
            began: _clock(),
          )..theirCamera = event['video'] == true;
          _wifiCheck(_call!);
          _watch();
          // Both called each other at once: the user wanted this call, so
          // it is answered at once.
          if (crossed) answer();
          changed = true;
        case 'call_ringing' when mine:
          call.phase = CallPhase.ringing;
          if (call.wifi) call._rang ??= _clock();
          changed = true;
        case 'call_answered' when mine:
          call
            ..words = _strings(event['words'])
            ..phase = CallPhase.live
            ..since = _clock();
          _startMedia();
          changed = true;
        case 'call_state' when mine:
          final screen = event['screen'] == true;
          if (call.theirScreen && !screen) _dropScreen(call.peer);
          call
            ..theyMuted = event['muted'] == true
            ..theirCamera = event['camera'] == true
            ..theirScreen = screen;
          if (!call.theirCamera) call.picture = null;
          changed = true;
        case 'call_ended' when mine:
          _finish(
            switch (event['reason']) {
              'declined' => CallEnd.declined,
              'busy' => CallEnd.busy,
              'unanswered' => CallEnd.unanswered,
              'no_wifi' => CallEnd.noWifi,
              'failed' => CallEnd.failed,
              _ => CallEnd.hangup,
            },
            // A call that only rang here and stopped is simply gone.
            show: call.phase != CallPhase.incoming,
          );
        case 'room' || 'room_in' || 'space':
          _readRooms();
          changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // Voice rooms

  /// Goes into a voice room, muted. Null if on the way in, or why not.
  CallProblem? joinRoom(String space, String channel) {
    final call = _call;
    if (call != null && call.phase != CallPhase.ended) return CallProblem.busy;
    final room = _room;
    if (room != null && room.space == space && room.channel == channel) {
      return null;
    }
    if (room != null) leaveRoom();
    final reply = _ask({
      'op': 'room_join',
      'space': space,
      'channel': channel,
      'muted': true,
    });
    if (reply == null) return CallProblem.refused;
    _room = RoomSession._(space, channel).._askedAt = _clock();
    _applyRoom(reply);
    // Sent once the room is known here: the key may come back at once.
    _pump.sendDeliveries(reply);
    _readRooms();
    _startMedia();
    _watch();
    notifyListeners();
    return null;
  }

  void leaveRoom() {
    final room = _room;
    if (room == null) return;
    _endSharing();
    _do({'op': 'room_leave', 'space': room.space, 'channel': room.channel});
    _room = null;
    _readRooms();
    if (_call == null || _call!.phase == CallPhase.ended) _stopMedia();
    notifyListeners();
  }

  void _applyRoom(Map<String, Object?> view) {
    final room = _room;
    if (room == null ||
        view['space'] != room.space ||
        view['channel'] != room.channel) {
      return;
    }
    room
      ..call = view['call'] as String? ?? room.call
      ..words = _strings(view['words']).isEmpty
          ? room.words
          : _strings(view['words']);
    final me = _myKey;
    room
      ..ownerMuted = _strings(view['owner_muted']).contains(me)
      ..ownerDeaf = _strings(view['owner_deaf']).contains(me);
  }

  String? _myKeyCache;
  String get _myKey => _myKeyCache ??= switch (_ask({'op': 'profile'})) {
    {'signing_key': final String key} => key,
    _ => '',
  };

  void _readRooms() {
    try {
      final rooms = _bridge.call({'op': 'rooms'});
      _rooms = rooms is List ? rooms.cast<Map<String, Object?>>() : const [];
    } on CoreException {
      _rooms = const [];
    }
    for (final view in _rooms) {
      _applyRoom(view);
    }
    _roomScreensChanged();
  }

  /// Everyone in a voice room as heard, the user not counted. With no
  /// room named, the one the user is in.
  List<RoomPerson> roomPeople([String? space, String? channel]) {
    space ??= _room?.space;
    channel ??= _room?.channel;
    final view = _rooms
        .where((r) => r['space'] == space && r['channel'] == channel)
        .firstOrNull;
    if (view == null) return const [];
    return [
      for (final p in (view['people'] as List? ?? const []).cast<Map>())
        RoomPerson(
          key: p['key'] as String,
          muted: p['muted'] == true,
          deaf: p['deaf'] == true,
          ownerMuted: p['owner_muted'] == true,
          ownerDeaf: p['owner_deaf'] == true,
          camera: p['camera'] == true,
          screen: p['screen'] == true,
        ),
    ];
  }

  void _roomTick({bool force = false}) {
    final room = _room;
    if (room == null) return;
    final now = _clock();
    if (!force && now.difference(room._toldAt) < times.roomEvery) return;
    room._toldAt = now;
    final reply = _do({
      'op': 'room_tick',
      'space': room.space,
      'channel': room.channel,
      'muted': room.muted || room.ownerMuted,
      'deaf': room.deaf,
      'screen': _sharing != null,
    });
    if (reply == null) {
      // No longer allowed in: removed from the space, or the room gone.
      _endSharing();
      _room = null;
      _forgetScreens();
      if (_call == null) _stopMedia();
      notifyListeners();
      return;
    }
    _applyRoom(reply);
    _readRooms();
  }

  // Keeping watch

  void _watch() {
    _watching ??= Timer.periodic(times.watchEvery, (_) => _check());
  }

  void _check() {
    var changed = false;
    final now = _clock();
    final call = _call;
    if (call != null && call.phase != CallPhase.ended) {
      final before = (call.wifi, call.showable);
      _wifiCheck(call);
      changed |= before != (call.wifi, call.showable);
      final age = now.difference(call.began);
      switch (call.phase) {
        case CallPhase.calling || CallPhase.ringing:
          if (!call.wifi && age > times.wifiWait) {
            _do({'op': 'call_end', 'call': call.id, 'reason': 'no_wifi'});
            _finish(CallEnd.noWifi);
          } else if (call._rang case final rang?
              when now.difference(rang) > times.ringFor) {
            _do({'op': 'call_end', 'call': call.id, 'reason': 'unanswered'});
            _finish(CallEnd.unanswered);
          } else if (!inRange(call.peer)) {
            _do({'op': 'call_end', 'call': call.id});
            _finish(CallEnd.lost);
          }
        case CallPhase.incoming:
          if (!call.wifi && age > times.wifiWait) {
            _do({'op': 'call_end', 'call': call.id, 'reason': 'no_wifi'});
            _finish(CallEnd.noWifi, show: false);
          } else if (age > times.wifiWait + times.ringFor ||
              !inRange(call.peer)) {
            _do({'op': 'call_end', 'call': call.id, 'reason': 'unanswered'});
            _finish(CallEnd.unanswered, show: false);
          }
        case CallPhase.live:
          if (call.wifi) {
            call._lostSince = null;
          } else {
            call._lostSince ??= now;
            if (now.difference(call._lostSince!) > times.lostAfter) {
              _do({'op': 'call_end', 'call': call.id});
              _finish(CallEnd.lost);
            }
          }
        case CallPhase.ended:
      }
    }
    final room = _room;
    if (room != null) {
      if (room.asking &&
          room._askedAt != null &&
          now.difference(room._askedAt!) > times.askWait) {
        // Nobody inside answered: the room is opened afresh.
        room._askedAt = null;
        final reply = _do({
          'op': 'room_join',
          'space': room.space,
          'channel': room.channel,
          'alone': true,
          'muted': room.muted,
        });
        if (reply != null) _applyRoom(reply);
        changed = true;
      }
      _roomTick();
      for (final person in roomPeople()) {
        if (fastLinkTo(person.key) == null && inRange(person.key)) {
          wantFast(person.key);
        }
      }
    } else if (_rooms.isNotEmpty) {
      // Someone may have gone quiet without a word.
      final before = _rooms.length;
      _readRooms();
      changed |= before != _rooms.length;
    }
    final speaking = _speakingNow();
    if (!setEquals(speaking, _speaking)) {
      _speaking = speaking;
      changed = true;
    }
    if (!busy && !(_clearing?.isActive ?? false) && _rooms.isEmpty) {
      _watching?.cancel();
      _watching = null;
    }
    if (changed) notifyListeners();
  }

  // Sound and pictures

  Future<void> _startMedia() async {
    if (_mediaOn) return;
    _mediaOn = true;
    final started = await audio.start(_heard);
    if (!_mediaOn) {
      await audio.stop();
      return;
    }
    _call?.micMissing = !started.mic;
    _room?.micMissing = !started.mic;
    _queues.clear();
    _primed.clear();
    _played = 0;
    _audioClock
      ..reset()
      ..start();
    _mixing ??= Timer.periodic(CallSound.block, (_) => _mix());
    final call = _call;
    if (call != null && call.video && call.camera) await _startCamera();
    notifyListeners();
  }

  Future<void> _startCamera() async {
    final camera = this.camera;
    if (camera == null) return;
    if (!await camera.start(_pictured)) {
      _call?.camera = false;
      notifyListeners();
    }
  }

  void _stopMedia() {
    _endSharing();
    if (!_mediaOn) return;
    _mediaOn = false;
    _mixing?.cancel();
    _mixing = null;
    _queues.clear();
    _levels.clear();
    audio.stop();
    camera?.stop();
  }

  /// Who to send to, and on which link, for whatever the user is in.
  String? get _sendingOn {
    final call = _call;
    if (call != null && call.phase == CallPhase.live) return call.id;
    final room = _room;
    if (room != null && !room.asking) return room.call;
    return null;
  }

  void _heard(Uint8List block) {
    final level = _levelOf(block);
    final call = _call;
    final room = _room;
    final muted = (call != null && call.phase == CallPhase.live)
        ? call.muted
        : room == null || room.muted || room.ownerMuted;
    _levels['me'] = (muted ? 0 : level, _clock());
    final on = _sendingOn;
    if (on == null || muted) return;
    _send(on, 'audio', block);
  }

  /// A picture goes as one byte for which way up it is, then the JPEG.
  void _pictured(Uint8List jpeg, int quarterTurns) {
    final call = _call;
    if (call == null || call.phase != CallPhase.live || !call.camera) return;
    if (jpeg.length + 1 > CallCamera.maxBytes) return;
    call
      ..myPicture = jpeg
      ..myPictureTurns = quarterTurns & 3;
    _send(call.id, 'video', Uint8List.fromList([quarterTurns & 3, ...jpeg]));
    notifyListeners();
  }

  void _send(String on, String kind, Uint8List data) {
    final sealed = _ask({
      'op': 'call_media_out',
      'call': on,
      'kind': kind,
      'data': hexOf(data),
    });
    if (sealed == null) return;
    final frame = sealed['frame']! as String;
    for (final peer in _strings(sealed['to'])) {
      final link = fastLinkTo(peer);
      if (link != null) _pump.sendMedia(link, frame);
    }
  }

  /// The highest frame number heard of each kind from each person in
  /// each call. A frame numbered no higher than the last is one heard
  /// before, played again by whoever is in the way, or one that came late
  /// and is of no use now. Either way it is dropped.
  final Map<String, int> _lastSeq = {};
  static const _mostSeqKeys = 64;

  /// Whether [seq] is newer than anything heard under [key]. Remembers it
  /// if so.
  bool _fresh(String key, int seq) {
    final last = _lastSeq[key];
    if (last != null && seq <= last) return false;
    if (last == null && _lastSeq.length >= _mostSeqKeys) {
      _lastSeq.remove(_lastSeq.keys.first);
    }
    _lastSeq[key] = seq;
    return true;
  }

  void _mediaIn(int link, String frame) {
    if (!_mediaOn) return;
    final got = _ask({'op': 'call_media_in', 'link': link, 'frame': frame});
    if (got == null) return;
    final from = got['from']! as String;
    // The core checked the frame is sealed for this call by this person.
    // What it cannot know is whether the same frame was heard already.
    final seq = got['seq'];
    if (seq is int && !_fresh('${got['call']}/$from/${got['kind']}', seq)) {
      return;
    }
    final data = bytesOf(got['data']! as String);
    if (got['kind'] == 'screen') {
      _screenIn(from, data);
      return;
    }
    if (got['kind'] == 'video') {
      final call = _call;
      if (call != null && call.peer == from && data.length > 1) {
        call
          ..pictureTurns = data[0] & 3
          ..picture = Uint8List.sublistView(data, 1);
        notifyListeners();
      }
      return;
    }
    _levels[from] = ((got['level'] as num?)?.toDouble() ?? 0, _clock());
    if (_room?.deaf ?? false) return;
    final queue = _queues.putIfAbsent(from, Queue.new);
    queue.add(Int16List.sublistView(data));
    while (queue.length > _keepBlocks) {
      queue.removeFirst();
    }
  }

  // Each person's sound waits in a queue of its own until a few blocks
  // are there, so a frame that comes a little late still plays in its
  // turn. Every fiftieth of a second one block is taken from each queue
  // and the blocks are added together for the speaker.

  static const _primeBlocks = 3;
  static const _keepBlocks = 12;
  final Map<String, Queue<Int16List>> _queues = {};
  final Set<String> _primed = {};
  final Stopwatch _audioClock = Stopwatch();
  int _played = 0;

  void _mix() {
    var due = _audioClock.elapsedMilliseconds ~/ 20 - _played;
    if (due > 5) {
      // Fell well behind: what was missed is not worth catching up on.
      _played += due - 5;
      due = 5;
    }
    for (var n = 0; n < due; n++) {
      _played++;
      final mixed = Int32List(CallSound.blockSamples);
      var any = false;
      for (final MapEntry(key: who, value: queue) in _queues.entries) {
        if (!_primed.contains(who)) {
          if (queue.length < _primeBlocks) continue;
          _primed.add(who);
        }
        if (queue.isEmpty) {
          _primed.remove(who);
          continue;
        }
        final block = queue.removeFirst();
        for (var i = 0; i < block.length && i < mixed.length; i++) {
          mixed[i] += block[i];
        }
        any = true;
      }
      if (!any) continue;
      final out = Int16List(CallSound.blockSamples);
      for (var i = 0; i < out.length; i++) {
        out[i] = mixed[i].clamp(-32768, 32767);
      }
      audio.play(out.buffer.asUint8List());
    }
  }

  // Sharing the screen

  ScreenSource? _sharing;
  Timer? _sharingTimer;
  bool _pumping = false;
  ScreenRate? _rate;
  Set<String> _watchers = const {};

  /// What the user is sharing, if anything.
  ScreenSource? get sharing => _sharing;

  /// Sharing was last stopped from outside the app: the window shared was
  /// closed, or the user stopped it from Android's notice.
  bool shareEnded = false;

  /// Why the user's screen could not be shared now, or null if it can.
  ShareProblem? get shareProblem {
    if (screen == null) return ShareProblem.unsupported;
    final call = _call;
    if (call != null && call.phase == CallPhase.live) {
      return call.wifi ? null : ShareProblem.needsWifi;
    }
    final room = _room;
    if (room == null || room.asking) return ShareProblem.notLive;
    final people = roomPeople();
    // Alone in a room, whoever comes in next sees it.
    if (people.isNotEmpty && people.every((p) => fastLinkTo(p.key) == null)) {
      return ShareProblem.needsWifi;
    }
    return null;
  }

  /// Starts sharing what the user picked. Null if it is being shared, or
  /// why not. [notice] is what Android's notice says while it goes on.
  Future<ShareProblem?> startSharing(
    ScreenSource source, {
    required ScreenNotice notice,
  }) async {
    final capture = screen;
    final problem = shareProblem;
    if (capture == null || problem != null) return problem;
    _endSharing();
    final watchers = _screenWatchers();
    final rate = ScreenRate.forWatchers(watchers.length);
    if (!await capture.start(source, rate: rate, notice: notice)) {
      return ShareProblem.failed;
    }
    // The call ended, or the room was left, while Android was asking.
    if (_sendingOn == null) {
      await capture.stop();
      return ShareProblem.notLive;
    }
    _sharing = source;
    shareEnded = false;
    _rate = rate;
    _watchers = watchers;
    _sharingTimer = Timer.periodic(times.shareEvery, (_) => _pumpScreen());
    _tellSharing();
    notifyListeners();
    return null;
  }

  /// Stops sharing the user's screen.
  void stopSharing() {
    if (_sharing == null) return;
    _endSharing();
    _tellSharing();
    notifyListeners();
  }

  void _endSharing() {
    if (_sharing == null) return;
    _sharing = null;
    _sharingTimer?.cancel();
    _sharingTimer = null;
    _rate = null;
    _watchers = const {};
    screen?.stop();
  }

  void _tellSharing() {
    final call = _call;
    if (call != null && call.phase == CallPhase.live) {
      _tell(call);
    } else if (_room != null) {
      _roomTick(force: true);
    }
  }

  /// Who sees the user's screen: everyone in the call or room a Wi-Fi
  /// link reaches.
  Set<String> _screenWatchers() {
    final call = _call;
    if (call != null && call.phase == CallPhase.live) {
      return {if (fastLinkTo(call.peer) != null) call.peer};
    }
    return {
      for (final person in roomPeople())
        if (fastLinkTo(person.key) != null && !person.ownerDeaf) person.key,
    };
  }

  Future<void> _pumpScreen() async {
    final capture = screen;
    if (capture == null || _sharing == null || _pumping) return;
    _pumping = true;
    try {
      final watchers = _screenWatchers();
      // Someone new is watching: they are sent the whole picture.
      if (watchers.difference(_watchers).isNotEmpty) capture.refresh();
      _watchers = watchers;
      final rate = ScreenRate.forWatchers(watchers.length);
      if (rate != _rate) {
        _rate = rate;
        capture.rate(rate);
      }
      final taken = await capture.take();
      if (_sharing == null) return;
      if (taken.state == ScreenState.ended ||
          taken.state == ScreenState.failed) {
        shareEnded = true;
        stopSharing();
        return;
      }
      final on = _sendingOn;
      if (on == null) return;
      for (final piece in taken.pieces) {
        _send(on, 'screen', piece.toFrame());
      }
    } finally {
      _pumping = false;
    }
  }

  final Map<String, SharedScreen> _screens = {};

  /// The picture each person last stopped sharing, so pieces of it still
  /// on their way are dropped.
  final Map<String, int> _stoppedGen = {};

  /// Who the room last said was sharing.
  Set<String> _roomSharers = const {};

  /// The screen [who] is sharing, once some of it has arrived.
  SharedScreen? screenOf(String who) {
    final shared = _screens[who];
    return shared != null && shared.hasPicture ? shared : null;
  }

  /// The screens shared in the voice room the user is in, in the order its
  /// people are listed.
  List<SharedScreen> get roomScreens => [
    for (final person in roomPeople()) ?screenOf(person.key),
  ];

  void _screenIn(String from, Uint8List data) {
    final piece = ScreenPiece.fromFrame(data);
    if (piece == null || _stoppedGen[from] == piece.gen) return;
    final call = _call;
    final inCall =
        call != null && call.peer == from && call.phase == CallPhase.live;
    if (!inCall && _room == null) return;
    final shared = _screens.putIfAbsent(from, () => SharedScreen(from));
    final first = !shared.hasPicture;
    shared.add(piece);
    // Later pieces redraw only the screen itself.
    if (first) notifyListeners();
  }

  void _dropScreen(String who) {
    final shared = _screens.remove(who);
    if (shared != null) _stoppedGen[who] = shared.gen;
  }

  void _forgetScreens() {
    _screens.clear();
    _roomSharers = const {};
  }

  /// Drops the screens of people who stopped sharing or left the room.
  void _roomScreensChanged() {
    final people = roomPeople();
    final inside = {for (final p in people) p.key};
    final sharing = {
      for (final p in people)
        if (p.screen) p.key,
    };
    final call = _call;
    for (final who in _screens.keys.toList()) {
      if (call != null && call.peer == who && call.phase == CallPhase.live) {
        continue;
      }
      if (!inside.contains(who) ||
          (_roomSharers.contains(who) && !sharing.contains(who))) {
        _dropScreen(who);
      }
    }
    _roomSharers = sharing;
  }

  // Who is speaking

  final Map<String, (double, DateTime)> _levels = {};
  Set<String> _speaking = const {};

  static const _speakingLevel = 0.015;
  static const _speakingFor = Duration(milliseconds: 400);

  Set<String> _speakingNow() {
    final now = _clock();
    return {
      for (final MapEntry(key: who, value: (level, at)) in _levels.entries)
        if (level >= _speakingLevel && now.difference(at) < _speakingFor) who,
    };
  }

  /// Whether this person is speaking right now. "me" is the user.
  bool speaking(String who) => _speaking.contains(who);

  /// Who of the people in a room is speaking: the loudest, if anyone.
  String? speakingIn(String space, String channel) {
    String? loudest;
    var most = 0.0;
    for (final person in roomPeople(space, channel)) {
      final (level, _) = _levels[person.key] ?? (0.0, _clock());
      if (_speaking.contains(person.key) && level > most) {
        most = level;
        loudest = person.key;
      }
    }
    return loudest;
  }

  static double _levelOf(Uint8List block) {
    final samples = Int16List.sublistView(block);
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in samples) {
      final s = sample / 32768;
      sum += s * s;
    }
    return math.sqrt(sum / samples.length);
  }

  static List<String> _strings(Object? list) =>
      list is List ? list.whereType<String>().toList() : const [];

  @override
  void dispose() {
    _watching?.cancel();
    _clearing?.cancel();
    _endSharing();
    _stopMedia();
    super.dispose();
  }
}
