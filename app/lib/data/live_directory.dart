import 'dart:io' show FileSystemException;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';

import '../calls/call_audio.dart';
import '../calls/call_camera.dart';
import '../calls/call_engine.dart';
import '../calls/screen_share.dart';
import '../core/core_bridge.dart';
import '../design/tokens.dart';
import '../radio/direct_wifi.dart';
import '../radio/fast_link.dart';
import '../radio/lan_radio.dart';
import '../radio/link_pump.dart';
import '../radio/link_traffic.dart';
import '../radio/lora/byte_link.dart';
import '../radio/lora/lora_radio.dart';
import '../radio/lora/radio_drivers.dart';
import 'safe_name.dart';
import '../radio/lora/radio_protocol.dart';
import '../radio/lora/radio_settings.dart';
import '../radio/lora/radio_transport.dart';
import '../radio/radio.dart';
import 'directory.dart';
import 'image_bounds.dart';
import 'live_mesh.dart';
import 'mesh.dart';
import 'models.dart';
import 'place.dart';
import 'stickers.dart';
import 'video_probe.dart';

/// The real people and chats: kept, sealed and checked by the Rust core,
/// and carried by a radio.
///
/// A person's id here is their signing key in hex. This class holds no keys
/// and makes no decisions about who may say what to whom. It asks the core,
/// shows what the core answers, and passes sealed envelopes to the radio.
class LiveDirectory extends Directory {
  LiveDirectory(
    this._bridge,
    this._pump, {
    DateTime Function()? clock,
    this.receivedDir,
    this.autoAcceptBytes = 10 * 1024 * 1024,
    this.wifi,
    this.fastFromBytes = 512 * 1024,
    this.privateDir,
    CallAudio? callAudio,
    CallCamera? callCamera,
    ScreenCapture? callScreen,
    CallTimes callTimes = const CallTimes(),
    Future<int> Function(String path)? videoProbe,
    RadioSettings radioSettings = const RadioSettings(),
    this.settingsDir,
    RadioTransport Function(RadioEndpoint endpoint)? makeTransport,
  }) : _clock = clock ?? DateTime.now,
       _videoProbe = videoProbe ?? probeVideoSeconds,
       _radioSettings = radioSettings,
       _makeTransport = makeTransport ?? RadioDrivers.make {
    _pump.onRadioOutcome(_radioOutcome);
    // A radio chosen last time is put back in place, off until the
    // long-range switch says otherwise.
    if (radioSettings.endpoint case final endpoint?) {
      _putRadio(endpoint, radioSettings.region);
    }
    calls = callAudio == null
        ? null
        : (CallEngine(
            bridge: _bridge,
            pump: _pump,
            audio: callAudio,
            camera: callCamera,
            screen: callScreen,
            fastLinkTo: _fastLinkTo,
            inRange: _inRange,
            wantFast: (peer) => _faster?.want(peer),
            times: callTimes,
            clock: _clock,
          )..addListener(_callsChanged));
    _pump
      ..onEvents(_onEvents)
      ..onRadioState(notifyListeners)
      ..onSignal(_signalSeen);
    refresh();
  }

  final CoreBridge _bridge;
  final DateTime Function() _clock;
  final LinkPump _pump;

  /// Reads how long a video on this device runs. The device's own player
  /// does it; tests put in their own.
  final Future<int> Function(String path) _videoProbe;

  // The LoRa radio

  /// Where radio.json is kept. Null: the choice is not kept.
  final String? settingsDir;
  RadioSettings _radioSettings;
  final RadioTransport Function(RadioEndpoint endpoint) _makeTransport;

  @override
  RadioSettings get radioSettings => _radioSettings;

  @override
  bool get canSetUpRadio => true;

  @override
  LoRaRadio? get lora => _pump.lora;

  /// Builds the radio for [endpoint] and puts it in the pump. Returns
  /// what went wrong, or null.
  Future<String?> _putRadio(RadioEndpoint endpoint, RadioRegion? region) async {
    final RadioTransport transport;
    try {
      transport = _makeTransport(endpoint);
    } on RadioException catch (e) {
      return e.message;
    }
    final lora = LoRaRadio(transport, region: region, clock: _clock);
    await _pump.setLora(lora);
    notifyListeners();
    return null;
  }

  @override
  Future<String?> setUpRadio(
    RadioEndpoint? endpoint, {
    RadioRegion? region,
  }) async {
    final next = endpoint == null
        ? _radioSettings.copyWith(clearEndpoint: true, regionCode: region?.code)
        : _radioSettings.copyWith(endpoint: endpoint, regionCode: region?.code);
    String? problem;
    if (endpoint == null) {
      await _pump.setLora(null);
    } else {
      problem = await _putRadio(endpoint, next.region);
      if (problem != null) return problem;
    }
    _radioSettings = next;
    if (settingsDir case final dir?) {
      try {
        next.save(dir);
      } on FileSystemException catch (e) {
        problem = 'the choice could not be kept: ${e.message}';
      }
    }
    notifyListeners();
    return problem;
  }

  /// How far each of the user's own messages sent by radio has got, by
  /// message id, and which radio frames belong to which message.
  final Map<String, RadioSendState> _radioStatus = {};
  final Map<String, String> _radioFrames = {};

  void _radioOutcome(RadioFrameOutcome outcome) {
    final id = _radioFrames[outcome.frame];
    if (id == null) return;
    _frameStates[outcome.frame] = outcome.state;
    // A message is as far as its least-far frame: failed as soon as one
    // is, delivered only once every one is, relayed once any is.
    final states = [
      for (final e in _radioFrames.entries)
        if (e.value == id) _frameStates[e.key] ?? RadioSendState.sent,
    ];
    final next = states.contains(RadioSendState.failed)
        ? RadioSendState.failed
        : states.every((s) => s == RadioSendState.delivered)
        ? RadioSendState.delivered
        : states.any(
            (s) => s == RadioSendState.relayed || s == RadioSendState.delivered,
          )
        ? RadioSendState.relayed
        : RadioSendState.sent;
    if (_radioStatus[id] == next) return;
    _radioStatus[id] = next;
    _threads.clear();
    notifyListeners();
  }

  final Map<String, RadioSendState> _frameStates = {};

  /// Notes that [delivery] carried the user's newest message to [chatId]
  /// by radio, so its outcome can be shown.
  void _trackRadio(String chatId, Delivery delivery) {
    if (delivery.transport != Transport.radio) return;
    _threads.remove(chatId);
    final id = _messages(chatId).where((m) => m.mine).lastOrNull?.id;
    if (id == null || id.isEmpty) return;
    for (final frame in delivery.frames) {
      _radioFrames[frame] = id;
    }
    _radioStatus[id] = RadioSendState.sent;
    while (_radioFrames.length > 2048) {
      final oldest = _radioFrames.keys.first;
      _radioFrames.remove(oldest);
      _frameStates.remove(oldest);
    }
    // The status of a message long gone from the screen is not kept.
    while (_radioStatus.length > 512) {
      _radioStatus.remove(_radioStatus.keys.first);
    }
  }

  /// How long each video runs, by path, once read. Zero: the device
  /// could not read it.
  final Map<String, int> _videoSeconds = {};
  final Set<String> _probing = {};

  /// The video at [path] as the Chats list shows it. Starts reading its
  /// length the first time it is asked for.
  VideoPreview _videoPreview(String path) {
    if (path.isEmpty) return const VideoPreview();
    final known = _videoSeconds[path];
    if (known != null) {
      return VideoPreview(path: path, seconds: known, failed: known == 0);
    }
    if (_probing.add(path)) {
      _videoProbe(path)
          .then<int>((seconds) => seconds, onError: (Object _) => 0)
          .then((seconds) {
            _videoSeconds[path] = seconds;
            _probing.remove(path);
            notifyListeners();
          });
    }
    return VideoPreview(path: path);
  }

  /// Where files the user receives are saved. With none, files cannot be
  /// accepted.
  @override
  final String? receivedDir;

  @override
  String? cleanPhoto(String path, String folder) =>
      switch (_ask({'op': 'photo_clean', 'path': path, 'dir': folder})) {
        {'cleaned': true, 'path': final String copy} => copy,
        _ => null,
      };

  @override
  (int, int) get carrying => switch (_ask({'op': 'carrying'})) {
    {'packets': final int packets, 'bytes': final int bytes} => (
      packets,
      bytes,
    ),
    _ => (0, 0),
  };

  /// A file from a contact no bigger than this is taken without asking.
  /// Anything bigger waits for the user to say yes.
  final int autoAcceptBytes;

  /// A folder of the app's own, which no other app is shown. Pictures
  /// sent to be seen once are kept here until they have been. With none,
  /// such a picture cannot be accepted.
  final String? privateDir;

  /// Wi-Fi Direct, on a device that has it. With none, two devices that
  /// share no network stay on Bluetooth.
  final DirectWifi? wifi;

  /// With this much of a file still to go to someone reached only over
  /// Bluetooth, the two set up Wi-Fi Direct. Less is not worth the wait.
  final int fastFromBytes;

  /// Whether the user has the fast link switched on, under Network.
  bool _wifiWanted = true;

  /// Made when first needed, once there is someone to be.
  FastLink? _fastLink;

  FastLink? get _faster {
    final wifi = this.wifi;
    if (wifi == null || !_wifiWanted) return null;
    if (_fastLink case final made?) return made;
    final me = switch (_ask({'op': 'profile'})) {
      {'signing_key': final String key} => key,
      _ => null,
    };
    if (me == null) return null;
    return _fastLink = FastLink(
      wifi: wifi,
      myId: me,
      ask: (to) => _sendNow({'op': 'fast_ask', 'to': to}),
      offer: (to, group, {required joins}) => _sendNow({
        'op': 'fast_offer',
        'to': to,
        'network': group.network,
        'pass': group.pass,
        'joins': joins,
      }),
      greet: _pump.reach,
      clock: _clock,
    );
  }

  /// Seals something worth sending only now, and sends it if the person
  /// is in range.
  void _sendNow(Map<String, Object?> request) {
    final envelope = _ask(request);
    if (envelope != null) _pump.deliver(envelope);
  }

  /// Whether a file is on offer or moving between the user and [id], and
  /// if [outgoing], whether enough of one the user is sending is left to
  /// be worth a faster link.
  bool _fileWith(String id, {bool outgoing = false}) => _transfers.values.any(
    (t) =>
        t['with'] == id &&
        _fileState(t['state']).active &&
        (!outgoing ||
            (t['incoming'] != true &&
                (t['size']! as int) - (t['done']! as int) >= fastFromBytes)),
  );

  /// Whether something between the user and [id] needs a fast link: a
  /// file on the way, or a call or voice room with them. Nothing else
  /// gets a group made for it, so a contact cannot have this device set
  /// one up for nothing.
  bool _wantsFast(String id) =>
      _fileWith(id) || (calls?.needsFastLink(id) ?? false);

  /// Sets about a faster link to someone in range, if the user is sending
  /// them something big and Bluetooth is all that reaches them.
  void _hurry(String id) {
    if (_inRange(id) && !_fast(id) && _fileWith(id, outgoing: true)) {
      _faster?.want(id);
    }
  }

  /// When the user last told each person they were typing, and when
  /// each person last said so themselves.
  final Map<String, int> _toldTyping = {};
  final Map<String, int> _typing = {};

  /// How long "typing" is believed, and how often it is said again. The
  /// same holds in a space's channels.
  static const typingFor = Duration(seconds: 5);
  static const typingEvery = Duration(seconds: 3);

  /// When each contact last said they have the app open.
  final Map<String, int> _here = {};
  static const _hereFor = Duration(seconds: 150);

  /// Whether the user has the app on screen.
  bool _active = false;

  bool _within(int? then, Duration time) =>
      then != null &&
      _clock().millisecondsSinceEpoch - then < time.inMilliseconds;

  @override
  void typing(String chatId) {
    if (!_inRange(chatId) || _within(_toldTyping[chatId], typingEvery)) return;
    _toldTyping[chatId] = _clock().millisecondsSinceEpoch;
    // The core makes nothing to send unless the user switched this on.
    _sendNow({'op': 'typing', 'to': chatId});
  }

  @override
  bool isTyping(String id) => _inRange(id) && _within(_typing[id], typingFor);

  @override
  void here({required bool active}) {
    _active = active;
    for (final id in _peers.keys) {
      if (_contacts.containsKey(id)) _sayHere(id);
    }
  }

  void _sayHere(String id) =>
      _sendNow({'op': 'here', 'to': id, 'active': _active});

  /// Every transfer the core knows of, by id. Null means ask again.
  Map<String, Map<String, Object?>>? _files;

  /// When each moving transfer was last seen to move, and how far it had
  /// got, for working out its speed.
  final Map<String, List<(int, int)>> _progress = {};

  /// Who is connected right now, and over which connections. Two devices
  /// can find each other at the same moment and end up with two.
  final Map<String, Set<int>> _peers = {};

  /// Contacts not in range who were heard from by way of another device:
  /// how many links away, through whom, and when. Believed for a few
  /// minutes, and no longer than the device in between stays in range.
  final Map<String, (int, String, int)> _heard = {};
  static const _heardFor = Duration(minutes: 10);

  /// Everyone met since the app started, so a stranger who walks off can
  /// still be named on a screen that was showing them.
  final Map<String, _Met> _met = {};

  Map<String, _Known> _contacts = {};
  Map<String, _Known> _incoming = {};
  Map<String, _Known> _outgoing = {};
  Set<String> _blocked = {};

  final Map<String, List<_Message>> _threads = {};
  final Map<String, int> _lastActive = {};
  final Map<String, List<String>> _words = {};
  final Set<String> _comparing = {};

  /// Notes to self, as last read from the core. They never leave the
  /// device. Null until first asked for, and again after any change.
  List<DirectItem>? _saved;

  @override
  RadioState get radioState => _pump.state;

  @override
  Future<void> allowRadio() async {
    if (await _pump.askPermission()) {
      _pump.stop();
      refresh();
    }
  }

  @override
  void retryRadio() {
    if (_pump.state == RadioState.on || _pump.state == RadioState.off) return;
    _pump.stop();
    refresh();
  }

  @override
  void refresh() {
    var wanted = false;
    try {
      if (_bridge.call({'op': 'profile'}) != null) {
        final settings = _bridge.call({'op': 'settings'});
        wanted = switch (settings) {
          {'links': {'bluetooth': final bool on}} => on,
          _ => false,
        };
        _status = switch (settings) {
          {'status': final String status} => MemberStatus.fromWire(status),
          _ => MemberStatus.online,
        };
        _myAway = switch (settings) {
          {'away': final String away} => away,
          _ => null,
        };
        // The local Wi-Fi link has its own switch.
        _wifiWanted = switch (settings) {
          {'links': {'wifi_nearby': final bool on}} => on,
          _ => true,
        };
        _pump.useNetwork(_wifiWanted);
        if (!_wifiWanted) _fastLink?.stop();
        // And so has the long-range radio. It starts off.
        _pump.useLora(switch (settings) {
          {'links': {'long_range': final bool on}} => on,
          _ => false,
        });
      }
    } on CoreException {
      // Nothing is open, so there is nobody to be.
    }
    if (wanted) {
      _pump.start();
    } else {
      _pump.stop();
    }
    // What is stored may have changed underneath, so nothing remembered
    // from before is trusted.
    _threads.clear();
    _files = null;
    _load();
    notifyListeners();
  }

  @override
  void reset() {
    _pump.stop();
    // Whoever the user was is gone, and so is any group made as them.
    _fastLink?.stop();
    _fastLink = null;
    _peers.clear();
    _heard.clear();
    _met.clear();
    _threads.clear();
    _files = null;
    _progress.clear();
    _lastActive.clear();
    _words.clear();
    _comparing.clear();
    _toldTyping.clear();
    _typing.clear();
    _photos.clear();
    _myPhoto = null;
    _myPhotoRead = false;
    _here.clear();
    _saved = null;
    refresh();
  }

  /// Reads contacts and requests back from the core.
  void _load() {
    try {
      final requests =
          _bridge.call({'op': 'requests'})! as Map<String, Object?>;
      _incoming = _known(requests['incoming']);
      _outgoing = _known(requests['outgoing']);
      _blocked = {...(requests['blocked']! as List).cast<String>()};
      _contacts = _known(_bridge.call({'op': 'contacts'}));
    } on CoreException {
      _incoming = {};
      _outgoing = {};
      _blocked = {};
      _contacts = {};
    }
  }

  static Map<String, _Known> _known(Object? list) => {
    for (final entry in (list! as List).cast<Map<String, Object?>>())
      entry['key']! as String: _Known(
        name: entry['name'] as String? ?? '',
        note: entry['note'] as String?,
        commonSpace: entry['common_space'] as String?,
        verified: entry['verified'] as bool? ?? false,
        verifiedBy: VerifyMethod.fromCore(entry['verified_by']),
        verifiedAt: switch (entry['verified_at']) {
          final int at => DateTime.fromMillisecondsSinceEpoch(at * 1000),
          _ => null,
        },
        timer: entry['timer'] as int? ?? 0,
        hidden: entry['hidden'] as bool? ?? false,
        away: entry['away'] as String?,
      ),
  };

  @override
  void sendOn(Object? reply) => _pump.sendDeliveries(reply);

  void _onEvents(List<Map<String, Object?>> events) {
    for (final event in events) {
      final from = event['from'] as String?;
      switch (event['kind']) {
        case 'peer':
          final key = event['key']! as String;
          final link = event['link']! as int;
          _peers.putIfAbsent(key, () => {}).add(link);
          // The first link to them this time round is how they were found.
          _foundOver.putIfAbsent(key, () => LinkNumbers.of(link));
          _met[key] = _Met(
            identity: event['identity']! as String,
            name: event['name'] as String?,
          );
          // Back in range with something big still to send.
          _hurry(key);
          // And told the user is here, if they are and allow it.
          if (_active && _contacts.containsKey(key)) _sayHere(key);
        case 'peer_gone':
          final key = event['key']! as String;
          final links = _peers[key];
          if (links == null) break;
          links.remove(event['link']);
          if (links.isEmpty) {
            _peers.remove(key);
            _foundOver.remove(key);
            _signals.remove(key);
            // Kept for Link trouble: when this person last went.
            (_drops[key] ??= []).add(_clock().millisecondsSinceEpoch);
            // Whoever was reached through this device no longer is.
            _heard.removeWhere((_, heard) => heard.$2 == key);
            // A comparison cut short cannot finish. Let it start afresh.
            if (!_words.containsKey(key)) _comparing.remove(key);
            _here.remove(key);
            _typing.remove(key);
          }
        case 'heard':
          _heard[from!] = (
            event['hops']! as int,
            event['via']! as String,
            _clock().millisecondsSinceEpoch,
          );
        case 'accepted':
          _lastActive[from!] = _stamp();
        case 'text':
          _threads.remove(from);
          _lastActive[from!] = _stamp();
          _typing.remove(from);
          // A new message brings a deleted chat back to the list.
          if (_contacts[from]?.hidden ?? false) _load();
        case 'typing':
          _typing[from!] = _clock().millisecondsSinceEpoch;
        case 'photo':
          _photos.remove(from);
        case 'here':
          if (event['active'] == true) {
            _here[from!] = _clock().millisecondsSinceEpoch;
          } else {
            _here.remove(from);
          }
        case 'delivered' || 'read' || 'voted' || 'unsent':
          _threads.remove(from);
        case 'file':
          _files = null;
          _threads.remove(from);
          _lastActive[from!] = _stamp();
          _onFile(event['id']! as String);
        case 'fast_ask':
          // Only someone in range, with a file on the way between the
          // two, gets a group made for them. So a contact cannot have
          // this device set one up for nothing.
          if (_inRange(from!) && !_fast(from) && _wantsFast(from)) {
            _faster?.asked(from);
          }
        case 'fast_offer':
          if (_inRange(from!) && !_fast(from) && _wantsFast(from)) {
            _faster?.offered(
              from,
              DirectGroup(
                event['network']! as String,
                event['pass']! as String,
              ),
              event['joins'] == true,
            );
          }
        case 'verify_started':
          // They began a comparison. Any words from an earlier one are
          // dead.
          _words.remove(from);
          _comparing.add(from!);
        case 'verify_ready':
          try {
            final reply =
                _bridge.call({'op': 'verify_words', 'with': from})!
                    as Map<String, Object?>;
            _words[from!] = (reply['words']! as List).cast<String>();
            _comparing.add(from);
          } on CoreException {
            _words.remove(from);
          }
      }
    }
    // Someone came or went, or told of who they hear: the devices in
    // range are told, where that is news to them.
    if (events.any(
      (e) => const {'peer', 'peer_gone', 'mesh'}.contains(e['kind']),
    )) {
      _shareMesh();
    }
    _load();
    notifyListeners();
  }

  /// The time in milliseconds, nudged so it never repeats or runs
  /// backwards. Two things that happen in the same instant still have an
  /// order.
  int _stamp() =>
      _latest = math.max(_clock().millisecondsSinceEpoch, _latest + 1);
  int _latest = 0;

  bool _inRange(String id) => _peers.containsKey(id);

  /// Calls and voice rooms, where this device has a microphone and
  /// speaker. Sound goes only over a fast link.
  @override
  late final CallEngine? calls;

  /// The fast link that reaches this person, if one does.
  int? _fastLinkTo(String id) =>
      _peers[id]?.where((link) => link >= LanRadio.firstLink).firstOrNull;

  /// A Wi-Fi group set up for a call is kept while the call goes on, and
  /// the screens hear of every change to a call.
  void _callsChanged() {
    _keepFast();
    notifyListeners();
  }

  void _keepFast() => _fastLink?.moving(
    _transfers.values.any((t) => _fileState(t['state']).active) ||
        (calls?.busy ?? false),
  );

  /// Whether a connection over the local network reaches this person. It
  /// is told by its number: see [LanRadio.firstLink].
  bool _fast(String id) =>
      _peers[id]?.any((link) => LinkNumbers.of(link) == Transport.wifi) ??
      false;

  /// Whether a LoRa radio is all that reaches [id].
  bool _radioOnly(String id) =>
      _peers[id]?.every((link) => LinkNumbers.of(link) == Transport.radio) ??
      false;

  /// The link each person in range was first found over this time.
  final Map<String, Transport> _foundOver = {};

  /// The link carrying to [id] now: the fastest that reaches them.
  Transport _transportTo(String id) => _fast(id)
      ? Transport.wifi
      : _radioOnly(id)
      ? Transport.radio
      : Transport.bluetooth;

  /// How someone can be reached right now: directly, through another
  /// device they were lately heard from by way of, or not at all.
  PersonLink _linkTo(String id) {
    if (_inRange(id)) {
      return switch (_transportTo(id)) {
        Transport.wifi => const PersonLink.wifi(),
        Transport.radio => const PersonLink.radio(),
        Transport.bluetooth => const PersonLink.bluetooth(),
      };
    }
    if (_heard[id] case (final hops, final via, final at)) {
      final age = _clock().millisecondsSinceEpoch - at;
      if (age <= _heardFor.inMilliseconds && _inRange(via)) {
        return PersonLink.relayed(hops: hops, viaId: via);
      }
    }
    return const PersonLink.outOfRange();
  }

  // People

  @override
  Person? find(String id) {
    final contact = _contacts[id];
    final asked = _incoming[id] ?? _outgoing[id];
    final met = _met[id];
    if (contact == null && asked == null && met == null) return null;
    // The name they gave when asking or accepting, else the one they let
    // strangers see, else their code words for now, made from their key.
    final name = [contact?.name, asked?.name, met?.name]
        .map((n) => n == null ? null : safeName(n))
        .firstWhere(
          (n) => n != null && n.isNotEmpty,
          orElse: () => codeWords(id, _clock())?.words ?? '',
        )!;
    return Person(
      id: id,
      name: name,
      tone: toneForKey(id),
      link: _linkTo(id),
      verified: contact?.verified ?? false,
      verifiedBy: contact?.verifiedBy,
      verifiedAt: contact?.verifiedAt,
      isContact: contact != null,
      online: _inRange(id) && _within(_here[id], _hereFor),
      photo: contact == null ? null : _photoOf(id),
      away: contact?.away,
    );
  }

  /// Code words already worked out, by key, with the moment they were
  /// asked for. They hold from then until they change.
  final Map<String, ({String words, DateTime from, DateTime until})>
  _codeWords = {};

  @override
  ({String words, DateTime until})? codeWords(String id, DateTime at) {
    if (_codeWords[id] case (:final words, :final from, :final until)
        when !at.isBefore(from) && at.isBefore(until)) {
      return (words: words, until: until);
    }
    final reply = _ask({
      'op': 'code_words',
      'key': id,
      'at': at.millisecondsSinceEpoch ~/ 1000,
    });
    if (reply case {'words': final String words, 'until': final int until}) {
      final ends = DateTime.fromMillisecondsSinceEpoch(until * 1000);
      _codeWords[id] = (words: words, from: at, until: ends);
      return (words: words, until: ends);
    }
    return null;
  }

  static int _byte(String id, int index) => id.length >= index * 2 + 2
      ? int.tryParse(id.substring(index * 2, index * 2 + 2), radix: 16) ?? 0
      : 0;

  @override
  List<Person> get nearbyPeople => [
    for (final id in _peers.keys)
      if (!_blocked.contains(id)) find(id)!,
    // Contacts reached through someone come before those not reached.
    for (final reached in [true, false])
      for (final id in _contacts.keys)
        if (!_inRange(id) && _linkTo(id).inRange == reached) find(id)!,
  ];

  /// The last few readings of how strongly each device in range is
  /// heard, by key, newest last.
  final Map<String, List<int>> _signals = {};

  /// How many readings are kept. The middle one of them is used, so one
  /// odd reading moves nobody.
  static const _readingsKept = 7;

  void _signalSeen(int link, int rssi) {
    final key = _peers.entries
        .where((entry) => entry.value.contains(link))
        .map((entry) => entry.key)
        .firstOrNull;
    if (key == null) return;
    final readings = _signals.putIfAbsent(key, () => [])..add(rssi);
    if (readings.length > _readingsKept) readings.removeAt(0);
    _shareMesh(soon: true);
    notifyListeners();
  }

  @override
  Nearness? nearness(String id) {
    final readings = _signals[id];
    if (readings == null || readings.isEmpty || !_peers.containsKey(id)) {
      return null;
    }
    final sorted = [...readings]..sort();
    return Nearness.fromRssi(sorted[sorted.length ~/ 2]);
  }

  @override
  bool get radarByDistance => _peers.keys.any((id) => nearness(id) != null);

  // The mesh, for the Nearby maps

  late final _meshTalk = LiveMesh(_bridge, _pump);

  /// The mesh as last read, with when, for a moment.
  (int, Mesh)? _meshRead;
  int _meshSharedAt = 0;

  /// Tells the devices in range who this one hears, where that is news
  /// to them. A new reading of a signal comes every couple of seconds
  /// from each device, so with [soon] it is not done more than once a
  /// second.
  void _shareMesh({bool soon = false}) {
    _meshRead = null;
    final now = _clock().millisecondsSinceEpoch;
    if (soon && (now - _meshSharedAt).abs() < 1000) return;
    _meshSharedAt = now;
    _meshTalk.share([
      for (final MapEntry(:key, value: links) in _peers.entries)
        (
          key: key,
          bluetooth: links.any((link) => link < LanRadio.firstLink),
          wifi: links.any((link) => link >= LanRadio.firstLink),
          near: nearness(key),
        ),
    ]);
  }

  @override
  Mesh get mesh {
    final now = _clock().millisecondsSinceEpoch;
    if (_meshRead case (final at, final read) when (now - at).abs() < 2000) {
      return read;
    }
    final own = [
      for (final MapEntry(:key, value: links) in _peers.entries)
        MeshLink(
          Mesh.me,
          key,
          bluetooth: links.any((link) => link < LanRadio.firstLink),
          wifi: links.any((link) => link >= LanRadio.firstLink),
          near: nearness(key),
        ),
    ];
    // Someone reached through a device in range, from a device that has
    // not told its map: the last step is known, if not by which radio.
    final heard = [
      for (final id in _contacts.keys)
        if (_linkTo(id) case PersonLink(hops: 2, :final viaId?)
            when !_inRange(id))
          MeshLink(viaId, id, bluetooth: true),
    ];
    final read = _meshTalk.read(own, more: heard);
    _meshRead = (now, read);
    return read;
  }

  /// When each person's last link went, newest last.
  final Map<String, List<int>> _drops = {};

  /// How long back Link trouble looks.
  static const _troubleWindow = Duration(minutes: 2);

  @override
  LinkTroubleReport? get linkTrouble {
    final now = _clock().millisecondsSinceEpoch;
    // Someone whose link went twice or more lately, and who came back in
    // between: not a person walking off, but links that will not hold.
    String? who;
    var most = 0;
    for (final MapEntry(:key, :value) in _drops.entries) {
      value.removeWhere((at) => now - at >= _troubleWindow.inMilliseconds);
      if (value.length >= 2 && value.length > most) {
        (who, most) = (key, value.length);
      }
    }
    if (who == null || _blocked.contains(who)) return null;
    final held = [
      for (final item in thread(who))
        if (item is DirectText && item.mine && !item.delivered) item,
    ].length;
    final readings = _signals[who] ?? const <int>[];
    final sorted = [...readings]..sort();
    final middle = sorted.isEmpty ? null : sorted[sorted.length ~/ 2];
    return LinkTroubleReport(
      bluetoothWorking:
          _pump.state == RadioState.on &&
          _peers.values.any(
            (links) => links.any((link) => link < LanRadio.firstLink),
          ),
      wifi24Working: false,
      wifi5Working: false,
      wifiNearbyWorking: _peers.values.any(
        (links) => links.any((link) => link >= LanRadio.firstLink),
      ),
      signalLevel: switch (middle) {
        null => 0,
        >= -55 => 5,
        >= -65 => 4,
        >= -75 => 3,
        >= -85 => 2,
        _ => 1,
      },
      signalPersonId: who,
      trend: _trendOf(readings),
      // Groups this device made again on the other band, lately.
      movedIds: _movedTo(WifiBand.high, now),
      movedToLowIds: _movedTo(WifiBand.low, now),
      heldCount: held,
      heldForIds: held > 0 ? [who] : const [],
    );
  }

  /// Who had the Wi-Fi Direct group moved onto [band] for them lately.
  List<String> _movedTo(WifiBand band, int now) => [
    ...{
      for (final move in _fastLink?.moves ?? const <BandMove>[])
        if (move.band == band &&
            now - move.at.millisecondsSinceEpoch <
                _troubleWindow.inMilliseconds)
          move.peer,
    },
  ];

  /// Better if the last three readings are louder than those before them
  /// by a few dB, worse if quieter, steady otherwise.
  static SignalTrend _trendOf(List<int> readings) {
    if (readings.length < 4) return SignalTrend.steady;
    double mean(Iterable<int> values) =>
        values.reduce((a, b) => a + b) / values.length;
    final last = mean(readings.skip(readings.length - 3));
    final before = mean(readings.take(readings.length - 3));
    if (last - before >= 4) return SignalTrend.better;
    if (before - last >= 4) return SignalTrend.worse;
    return SignalTrend.steady;
  }

  @override
  bool get canRestartRadios => true;

  @override
  void restartRadios() {
    _pump.stop();
    refresh();
  }

  @override
  Offset? radarPosition(String id) {
    final link = _linkTo(id);
    if (!link.inRange || _blocked.contains(id)) return null;
    // Bluetooth gives no direction, so where on its ring someone is drawn
    // is only a steady spot for each person, not where they are standing.
    // How far from the middle follows how strongly they are heard, once
    // that is known. Someone reached through another device is drawn
    // furthest out.
    final angle = (_byte(id, 1) * 256 + _byte(id, 2)) / 65536 * 2 * math.pi;
    final radius = link.kind == LinkKind.relayed
        ? 70.0
        : switch (nearness(id)) {
            Nearness.veryClose => 30.0,
            Nearness.near => 48.0,
            Nearness.far => 66.0,
            null => 36.0 + (_byte(id, 3) % 2) * 14,
          };
    const centre = 88.0, half = 15.0;
    return Offset(
      centre + radius * math.cos(angle) - half,
      centre + radius * math.sin(angle) - half,
    );
  }

  @override
  String? sameNameAs(String id) {
    // Compared as shown, so a name made different only by characters that
    // show as nothing still counts as the same name.
    String plain(String? name) => safeName(name ?? '').toLowerCase();
    final name = plain(
      _contacts[id]?.name ??
          _incoming[id]?.name ??
          _outgoing[id]?.name ??
          _met[id]?.name,
    );
    if (name.isEmpty) return null;
    for (final MapEntry(:key, :value) in _contacts.entries) {
      if (key != id && plain(value.name) == name) return key;
    }
    return null;
  }

  // Requests

  @override
  List<IncomingRequest> get incomingRequests => [
    for (final entry in _incoming.entries)
      IncomingRequest(
        personId: entry.key,
        note: entry.value.note,
        commonSpace: entry.value.commonSpace,
      ),
  ];

  @override
  List<Person> get outgoingRequests => [
    for (final id in _outgoing.keys) find(id)!,
  ];

  @override
  bool isBlocked(String id) => _blocked.contains(id);

  /// Asks the core to do something that may produce an envelope, sends the
  /// envelope if there is one, and shows the result. A refusal by the core
  /// changes nothing.
  void _act(Map<String, Object?> request, {void Function()? then}) {
    try {
      final envelope = _bridge.call(request);
      if (envelope != null) _pump.deliver(envelope);
      then?.call();
    } on CoreException {
      // The core said no: not a contact, blocked, nothing to answer.
    }
    _load();
    notifyListeners();
  }

  @override
  void sendRequest(String id) {
    final identity = _met[id]?.identity;
    if (identity == null) return;
    _act({'op': 'request_chat', 'identity': identity});
  }

  static const _linkPrefix = 'dnet:id/';
  static const _invitePrefix = 'dnet:invite/';

  @override
  String? newInviteLink() => switch (_ask({'op': 'invite_link'})) {
    {'link': final String link} => link,
    _ => null,
  };

  /// Asks the maker of a one-time link to chat. [tapped]: the link came
  /// off their own phone, tapped against this one.
  LinkRequest _requestByInvite(String link, {bool tapped = false}) {
    final Object? read;
    try {
      read = _bridge.call({'op': 'check_invite', 'link': link});
    } on CoreException {
      return LinkRequest.notALink;
    }
    if (read is! Map) return LinkRequest.notALink;
    final key = read['key'];
    if (myLink case final mine? when key is String && mine.contains(key)) {
      return LinkRequest.yourself;
    }
    if (_contacts.containsKey(key)) return LinkRequest.alreadyContact;
    if (read['expired'] == true) return LinkRequest.ranOut;
    final Object? envelope;
    try {
      envelope = _bridge.call({
        'op': 'request_by_invite',
        'link': link,
        'scanned': tapped,
      });
    } on CoreException {
      return LinkRequest.notALink;
    }
    _pump.deliver(envelope);
    _load();
    notifyListeners();
    return LinkRequest.sent;
  }

  @override
  String? get myLink => switch (_ask({'op': 'card'})) {
    {'identity': final String identity} => '$_linkPrefix$identity',
    _ => null,
  };

  @override
  bool verifyScanned(String link) =>
      link.startsWith(_linkPrefix) &&
      _verifyIdentity(link.substring(_linkPrefix.length), 'qr');

  @override
  LinkRequest requestTapped(String link) {
    final text = link.trim();
    if (text.startsWith(_invitePrefix)) {
      return _requestByInvite(text, tapped: true);
    }
    return requestByLink(text, scanned: true, how: 'tap');
  }

  @override
  bool verifyTapped(String link) {
    final text = link.trim();
    if (text.startsWith(_linkPrefix)) {
      return _verifyIdentity(text.substring(_linkPrefix.length), 'tap');
    }
    if (!text.startsWith(_invitePrefix)) return false;
    return switch (_ask({'op': 'check_invite', 'link': text})) {
      {'identity': final String identity} => _verifyIdentity(identity, 'tap'),
      _ => false,
    };
  }

  /// Verifies a contact if [identity], read off their own device, is the
  /// one held for them. [how] is "qr" or "tap".
  bool _verifyIdentity(String identity, String how) {
    final Object? reply;
    try {
      reply = _bridge.call({
        'op': 'verify_scanned',
        'identity': identity,
        'how': how,
      });
    } on CoreException {
      return false;
    }
    final verified = reply is Map && reply['verified'] == true;
    if (verified) {
      _load();
      notifyListeners();
    }
    return verified;
  }

  /// Profile photos of contacts, by key, as last read. Null: none shown.
  final Map<String, Uint8List?> _photos = {};
  Uint8List? _myPhoto;
  bool _myPhotoRead = false;

  static Uint8List? _bytesOfHex(Object? hex) {
    if (hex is! String || hex.isEmpty || hex.length.isOdd) return null;
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      bytes[i] = byte;
    }
    return bytes;
  }

  static String _hexOf(Uint8List bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  Uint8List? _photoOf(String id) => _photos.putIfAbsent(
    id,
    () => switch (_ask({'op': 'photo_of', 'who': id})) {
      // A photo came from their device. One that claims a huge size is
      // not decoded: see image_bounds.dart.
      {'photo': final Object? photo} => switch (_bytesOfHex(photo)) {
        final bytes? when soundImage(bytes) => bytes,
        _ => null,
      },
      _ => null,
    },
  );

  @override
  Uint8List? get myPhoto {
    if (!_myPhotoRead) {
      _myPhotoRead = true;
      _myPhoto = switch (_ask({'op': 'my_photo'})) {
        {'photo': final Object? photo} => _bytesOfHex(photo),
        _ => null,
      };
    }
    return _myPhoto;
  }

  @override
  bool setMyPhoto(Uint8List photo) {
    final Object? reply;
    try {
      reply = _bridge.call({'op': 'photo_set', 'photo': _hexOf(photo)});
    } on CoreException {
      return false;
    }
    // Contacts are sent it, and the user's spaces are told.
    _pump.sendDeliveries(reply);
    _myPhoto = photo;
    _myPhotoRead = true;
    notifyListeners();
    return true;
  }

  @override
  void clearMyPhoto() {
    final reply = _ask({'op': 'photo_clear'});
    if (reply != null) _pump.sendDeliveries(reply);
    _myPhoto = null;
    _myPhotoRead = true;
    notifyListeners();
  }

  @override
  LinkRequest requestScanned(String id, {bool verify = true}) {
    final identity = _met[id]?.identity;
    if (identity == null) return LinkRequest.notALink;
    return requestByLink('$_linkPrefix$identity', scanned: verify);
  }

  @override
  bool verifyKey(String id) {
    final reply = _ask({'op': 'verify_key', 'key': id});
    final verified = reply is Map && reply['verified'] == true;
    if (verified) {
      _load();
      notifyListeners();
    }
    return verified;
  }

  @override
  LinkRequest requestByLink(
    String link, {
    bool scanned = false,
    String? knownAs,
    // With [scanned]: "qr" or "tap", for how they will have been verified.
    String how = 'qr',
  }) {
    final text = link.trim();
    if (text.startsWith(_invitePrefix)) return _requestByInvite(text);
    if (!text.startsWith(_linkPrefix)) return LinkRequest.notALink;
    final identity = text.substring(_linkPrefix.length);
    if (text == myLink) return LinkRequest.yourself;
    // A public identity starts with one byte for its format and then the
    // signing key, which is what a person is known by here.
    if (identity.length > 66 &&
        _contacts.containsKey(identity.substring(2, 66))) {
      return LinkRequest.alreadyContact;
    }
    final Object? envelope;
    try {
      // The core checks the identity holds together before using it.
      envelope = _bridge.call({
        'op': 'request_chat',
        'identity': identity,
        'scanned': scanned,
        'known_as': ?knownAs,
        if (scanned) 'how': how,
      });
    } on CoreException {
      return LinkRequest.notALink;
    }
    // Kept until it reaches them, by way of others if need be.
    _pump.deliver(envelope);
    _load();
    notifyListeners();
    return LinkRequest.sent;
  }

  @override
  void cancelOutgoingRequest(String id) =>
      _act({'op': 'cancel_request', 'to': id});

  @override
  void acceptRequest(String id) => _act({
    'op': 'accept',
    'from': id,
  }, then: () => _lastActive[id] = _stamp());

  @override
  void declineRequest(String id) => _act({'op': 'decline', 'from': id});

  @override
  List<Person> get blockedPeople {
    final Object? reply;
    try {
      reply = _bridge.call({'op': 'blocked'});
    } on CoreException {
      return const [];
    }
    if (reply is! List) return const [];
    return [
      for (final entry in reply.cast<Map<String, Object?>>())
        Person(
          id: entry['key']! as String,
          // Someone blocked before they ever gave a name has none.
          name: switch (safeName(entry['name'] as String? ?? '')) {
            final name when name.isNotEmpty => name,
            _ => (entry['key']! as String).substring(0, 8),
          },
          tone: toneForKey(entry['key']! as String),
          link: const PersonLink.outOfRange(),
        ),
    ];
  }

  @override
  void unblockPerson(String id) => _act({'op': 'unblock', 'who': id});

  @override
  ({String code, List<String> words})? checkCode(String id) {
    try {
      return switch (_bridge.call({'op': 'check_code', 'with': id})) {
        {'code': final String code, 'words': final List<Object?> words} => (
          code: code,
          words: words.cast<String>(),
        ),
        _ => null,
      };
    } on CoreException {
      return null;
    }
  }

  @override
  bool checkPastedCode(String id, String pasted) {
    final Object? reply;
    try {
      reply = _bridge.call({'op': 'check_paste', 'with': id, 'code': pasted});
    } on CoreException {
      return false;
    }
    final matched = reply is Map && reply['matched'] == true;
    if (matched) {
      _load();
      notifyListeners();
    }
    return matched;
  }

  @override
  void blockPerson(String id) => _act(
    {'op': 'block', 'who': id},
    then: () {
      _threads.remove(id);
      _words.remove(id);
      _comparing.remove(id);
    },
  );

  // Messages

  List<_Message> _messages(String id) {
    if (!_contacts.containsKey(id)) return const [];
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    // Something remembered from before may have run out of time since.
    if (_threads[id]?.any((m) => (m.goneAt ?? now + 1) <= now) ?? false) {
      _threads.remove(id);
    }
    return _threads.putIfAbsent(id, () {
      try {
        // Whatever has run out of time is deleted before anything is
        // read, so it is never shown again.
        _bridge.call({'op': 'expire', 'now': now});
        final stored = _bridge.call({'op': 'thread', 'with': id})! as List;
        return [
          for (final m in stored.cast<Map<String, Object?>>())
            _Message(
              file: switch (m['file']) {
                {'id': final String id} => id,
                _ => null,
              },
              mine: m['mine']! as bool,
              body: m['body']! as String,
              sentAt: m['sent_at']! as int,
              delivered: m['delivered'] as bool? ?? false,
              read: m['read'] as bool? ?? false,
              seen: m['seen'] as bool? ?? true,
              id: m['id'] as String? ?? '',
              options: ((m['options'] as List?) ?? const []).cast<String>(),
              myVote: m['my_vote'] as int?,
              theirVote: m['their_vote'] as int?,
              goneAt: m['gone_at'] as int?,
              deleted: m['deleted'] as bool? ?? false,
              forwarded: m['forwarded'] as bool? ?? false,
              card: switch (m['card']) {
                {
                  'name': final String name,
                  'identity': final String identity,
                  'key': final String key,
                } =>
                  (name, identity, key),
                _ => null,
              },
              location: Place.fromWire(m['location']),
              sticker: stickerFromWire(m['sticker']),
            ),
        ];
      } on CoreException {
        return const [];
      }
    });
  }

  String _clockTime(int sentAt) => DateFormat.Hm().format(
    DateTime.fromMillisecondsSinceEpoch(sentAt * 1000),
  );

  /// The time for today's messages, the date for older ones.
  String _when(int sentAt) {
    final then = DateTime.fromMillisecondsSinceEpoch(sentAt * 1000);
    final now = _clock();
    final today =
        then.year == now.year && then.month == now.month && then.day == now.day;
    return today
        ? DateFormat.Hm().format(then)
        : DateFormat.MMMd().format(then);
  }

  @override
  List<ChatSummary> get chats {
    final rows = <(int, int, ChatSummary)>[];
    var index = 0;
    for (final MapEntry(key: id, value: known) in _contacts.entries) {
      if (known.hidden) continue;
      final last = _messages(id).lastOrNull;
      final transfer = switch (last?.file) {
        final file? => _transfers[file],
        null => null,
      };
      final fileName = transfer == null
          ? null
          : transfer['name'] as String? ?? '';
      final voice = fileName == null ? null : voiceSecondsIn(fileName);
      final video =
          fileName != null && voice == null && DirectFile.isVideoName(fileName)
          ? _videoPreview(
              transfer!['state'] == 'done'
                  ? transfer['path'] as String? ?? ''
                  : '',
            )
          : null;
      final isLocation = last != null && last.location != null;
      final isPoll = last != null && !last.deleted && last.options.isNotEmpty;
      final kind = last != null && last.deleted
          ? PreviewKind.deleted
          : voice != null
          ? PreviewKind.voice
          : video != null
          ? PreviewKind.video
          : fileName != null
          ? PreviewKind.file
          : isLocation
          ? PreviewKind.location
          : isPoll
          ? PreviewKind.poll
          : last?.sticker != null
          ? PreviewKind.sticker
          : PreviewKind.text;
      rows.add((
        _lastActive[id] ?? (last?.sentAt ?? 0) * 1000,
        index++,
        ChatSummary(
          personId: id,
          previewKind: kind,
          previewText: voice != null
              ? formatSeconds(voice)
              : fileName ?? last?.body ?? '',
          time: last == null ? '' : _when(last.sentAt),
          unread: _messages(id).where((m) => !m.mine && !m.seen).length,
          disappearing: timerFor(id) > 0,
          video: video,
          // A place deleted for everyone is shown as gone.
          place: isLocation && !last.deleted ? last.location : null,
          poll: isPoll
              ? Poll(
                  question: last.body,
                  options: [
                    for (final (i, label) in last.options.indexed)
                      PollOption(
                        label,
                        (last.myVote == i ? 1 : 0) +
                            (last.theirVote == i ? 1 : 0),
                      ),
                  ],
                  myChoice: last.myVote,
                )
              : null,
        ),
      ));
    }
    // Most recently active first; otherwise the order the core lists them.
    rows.sort((a, b) {
      final byTime = b.$1.compareTo(a.$1);
      return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
    });
    return [for (final row in rows) row.$3];
  }

  @override
  List<DirectItem> thread(String chatId) {
    if (chatId == savedMessagesId) return _saved ??= _notes();
    return [
      for (final m in _messages(chatId))
        if (m.file case final file?)
          // A file whose transfer has been forgotten is left out, rather
          // than shown with nothing known about it.
          ?_fileItem(file, m)
        else if (m.card case (final name, final identity, final key)?)
          DirectCard(
            personId: key,
            name: safeName(name),
            identity: identity,
            time: _clockTime(m.sentAt),
            mine: m.mine,
          )
        else if (m.location case final place? when !m.deleted)
          DirectLocation(
            id: m.id,
            place: place,
            time: _clockTime(m.sentAt),
            mine: m.mine,
            delivered: m.delivered,
            read: m.read,
            canDeleteForEveryone:
                m.mine &&
                _clock().millisecondsSinceEpoch ~/ 1000 - m.sentAt <
                    _unsendWindow,
          )
        else if (m.options.isNotEmpty)
          DirectPoll(
            id: m.id,
            time: _clockTime(m.sentAt),
            mine: m.mine,
            poll: Poll(
              question: m.body,
              // Two people, so each choice has none, one or two votes.
              options: [
                for (final (index, label) in m.options.indexed)
                  PollOption(
                    label,
                    (m.myVote == index ? 1 : 0) +
                        (m.theirVote == index ? 1 : 0),
                  ),
              ],
              myChoice: m.myVote,
            ),
          )
        else
          DirectText(
            id: m.id,
            text: m.body,
            time: _clockTime(m.sentAt),
            mine: m.mine,
            deleted: m.deleted,
            forwarded: m.forwarded,
            radioStatus: m.mine ? _radioStatus[m.id] : null,
            sticker: m.deleted ? null : m.sticker,
            canDeleteForEveryone:
                m.mine &&
                !m.deleted &&
                _clock().millisecondsSinceEpoch ~/ 1000 - m.sentAt <
                    _unsendWindow,
            delivered: m.delivered,
            read: m.read,
            disappears: m.goneAt != null,
            goneInSeconds: m.goneAt == null
                ? 0
                : (m.goneAt! - _clock().millisecondsSinceEpoch ~/ 1000).clamp(
                    0,
                    1 << 31,
                  ),
          ),
    ];
  }

  @override
  bool sendSticker(String chatId, Sticker sticker) {
    final envelope = _ask({
      'op': 'send_text',
      'to': chatId,
      'sticker': stickerToWire(sticker),
    });
    if (envelope == null) return false;
    _pump.deliver(envelope);
    _threads.remove(chatId);
    _lastActive[chatId] = _stamp();
    notifyListeners();
    return true;
  }

  @override
  bool sendLocation(String chatId, Place place) {
    final envelope = _ask({
      'op': 'send_location',
      'to': chatId,
      'location': place.toWire(),
    });
    if (envelope == null) return false;
    _pump.deliver(envelope);
    _threads.remove(chatId);
    _lastActive[chatId] = _stamp();
    notifyListeners();
    return true;
  }

  @override
  bool sendCard(String chatId, String contactId) {
    final envelope = _ask({
      'op': 'send_card',
      'to': chatId,
      'contact': contactId,
    });
    if (envelope == null) return false;
    _pump.deliver(envelope);
    _threads.remove(chatId);
    _lastActive[chatId] = _stamp();
    notifyListeners();
    return true;
  }

  @override
  int timerFor(String chatId) => _contacts[chatId]?.timer ?? 0;

  /// How long the user's own messages can be deleted for everyone, in
  /// seconds. The core keeps to the same.
  static const _unsendWindow = 2 * 24 * 60 * 60;

  @override
  void deleteForMe(String chatId, List<String> ids) {
    _ask({'op': 'chat_delete_mine', 'with': chatId, 'ids': ids});
    _threads.remove(chatId);
    notifyListeners();
  }

  @override
  bool deleteForEveryone(String chatId, List<String> ids) {
    final envelope = _ask({'op': 'chat_unsend', 'with': chatId, 'ids': ids});
    if (envelope == null) return false;
    // Kept by the core until the other device has it.
    _pump.deliver(envelope);
    _threads.remove(chatId);
    notifyListeners();
    return true;
  }

  @override
  void clearChat(String chatId) {
    _ask({'op': 'chat_clear', 'with': chatId});
    _threads.remove(chatId);
    notifyListeners();
  }

  @override
  List<String> get hiddenChats => [
    for (final MapEntry(:key, :value) in _contacts.entries)
      if (value.hidden) key,
  ];

  @override
  void deleteChat(String chatId) {
    _ask({'op': 'chat_delete', 'with': chatId});
    _threads.remove(chatId);
    _load();
    notifyListeners();
  }

  @override
  bool setTimer(String chatId, int seconds) {
    final envelope = _ask({
      'op': 'set_timer',
      'with': chatId,
      'seconds': seconds,
    });
    if (envelope == null) return false;
    _pump.deliver(envelope);
    _load();
    notifyListeners();
    return true;
  }

  // Files

  Map<String, Map<String, Object?>> get _transfers => _files ??= {
    for (final t in switch (_ask({'op': 'files'})) {
      final List<Object?> list => list.cast<Map<String, Object?>>(),
      _ => const <Map<String, Object?>>[],
    })
      t['id']! as String: t,
  };

  Object? _ask(Map<String, Object?> request) {
    try {
      return _bridge.call(request);
    } on CoreException {
      return null;
    }
  }

  static FileState _fileState(Object? state) => switch (state) {
    'asked' => FileState.asked,
    'offered' => FileState.offered,
    'sending' || 'receiving' => FileState.moving,
    'paused' => FileState.paused,
    'done' => FileState.done,
    'declined' => FileState.declined,
    'cancelled' => FileState.cancelled,
    _ => FileState.failed,
  };

  DirectFile? _fileItem(String id, _Message message) {
    final t = _transfers[id];
    if (t == null) return null;
    return DirectFile(
      id: id,
      name: t['name']! as String,
      size: t['size']! as int,
      done: t['done']! as int,
      state: _fileState(t['state']),
      time: _clockTime(message.sentAt),
      mine: message.mine,
      path: t['path'] as String? ?? '',
      once: t['once'] == true,
      viewed: t['viewed'] == true,
    );
  }

  /// Asks the core to do something about a file, sends on whatever that
  /// produces, and shows the result. False if the core refused.
  bool _file(Map<String, Object?> request) {
    final Object? reply;
    try {
      reply = _bridge.call(request);
    } on CoreException {
      return false;
    }
    _pump
      ..sendDeliveries(reply)
      ..poll();
    _files = null;
    _threads.clear();
    notifyListeners();
    return true;
  }

  /// Whether a small file from [id] may be taken without asking. Not from
  /// someone unverified, if the user chose that.
  bool _mayTakeFileFrom(String id) => switch (_ask({'op': 'settings'})) {
    {'safety': {'verified_files_only': true}} =>
      _contacts[id]?.verified ?? false,
    _ => true,
  };

  /// A transfer changed. Notes how far it has got, and takes a small file
  /// from a contact without asking.
  void _onFile(String id) {
    final t = _transfers[id];
    if (t == null) return;
    final state = _fileState(t['state']);
    if (state == FileState.moving) {
      final seen = _progress.putIfAbsent(id, () => []);
      seen.add((_clock().millisecondsSinceEpoch, t['done']! as int));
      // The last few seconds say how fast it is going now.
      if (seen.length > 20) seen.removeAt(0);
    } else {
      _progress.remove(id);
    }
    if (state == FileState.asked &&
        t['incoming'] == true &&
        (t['size']! as int) <= autoAcceptBytes &&
        _mayTakeFileFrom(t['with']! as String)) {
      answerFile(id, accept: true);
    }
    _hurry(t['with']! as String);
    _keepFast();
  }

  @override
  bool sendFile(String chatId, String path, {bool once = false}) {
    final sent = _file({
      'op': 'file_send',
      'to': chatId,
      'path': path,
      'once': once,
    });
    if (sent) {
      _lastActive[chatId] = _stamp();
      // Begun while they decide, so it is ready when they say yes.
      _hurry(chatId);
    }
    return sent;
  }

  @override
  void viewedOnce(String id) => _file({'op': 'file_viewed', 'id': id});

  @override
  void answerFile(String id, {required bool accept}) {
    // A picture to be seen once is not put where other apps can open it.
    final dir = _transfers[id]?['once'] == true ? privateDir : receivedDir;
    if (accept && dir == null) return;
    _file(
      accept
          ? {'op': 'file_accept', 'id': id, 'dir': dir}
          : {'op': 'file_decline', 'id': id},
    );
  }

  @override
  void cancelFile(String id) => _file({'op': 'file_cancel', 'id': id});

  @override
  void pauseFile(String id, {required bool paused}) =>
      _file({'op': paused ? 'file_pause' : 'file_resume', 'id': id});

  /// Whether anyone in range can be reached over the local network.
  @override
  bool get hasFastLink => _peers.keys.any(_fast);

  /// What is built so far, of everything the Privacy and Network screens
  /// offer or promise. Add to this only when the thing really works.
  static const _built = <Object>{
    SharingSetting.findByName,
    SharingSetting.addToGroups,
    SharingSetting.readReceipts,
    SharingSetting.screenshots,
    SharingSetting.typing,
    SharingSetting.showOnline,
    SharingSetting.showPhoto,
    DeviceSetting.appLock,
    DeviceSetting.autoDelete,
    DeviceSetting.eraseOnWrongPasscode,
    DeviceSetting.notifications,
    DeviceSetting.notifyText,
    DeviceSetting.background,
    SafetySetting.autoVerify,
    SafetySetting.relay,
    SafetySetting.verifiedFilesOnly,
    LinkSetting.bluetooth,
    LinkSetting.wifiNearby,
    LinkProtection.holdsMessages,
    // Chat goes on Bluetooth and Wi-Fi at once, files on the faster, and
    // a file is put together from pieces that came by any way.
    LinkProtection.bothRadios,
    LinkProtection.rebuildsFiles,
    AlwaysOn.chatEncryption,
    AlwaysOn.postQuantumKeys,
    AlwaysOn.encryptedStorage,
    AlwaysOn.keyChangeAlerts,
    Extra.storageDetails,
    Extra.namesInSpaces,
    Extra.shareContact,
    Extra.stripPhotoLocation,
    Extra.viewOnce,
    Extra.forwarding,
    Extra.memberStatus,
    // The core sends places. Whether this device can find one is the
    // app's to say: see AppState.works.
    Extra.shareLocation,
    Extra.spaceIcons,
    Extra.stickers,
    Extra.emojiReactions,
    Extra.videos,
  };

  @override
  bool works(Object feature) =>
      _built.contains(feature) ||
      // Calls work wherever there is a microphone and speaker the app
      // can use, and video wherever there is a camera as well.
      (calls != null &&
          (feature == Extra.calls || feature == Extra.voiceRooms)) ||
      (feature == Extra.videoCalls && (calls?.canVideo ?? false)) ||
      // Only a device that can choose where its Wi-Fi Direct group goes
      // can move it off a crowded band. A PC cannot.
      (feature == LinkProtection.changesBand && (wifi?.canChooseBand ?? false));

  @override
  ValueListenable<LinkTraffic>? get linkTraffic => _pump.traffic;

  @override
  Transfer? get transfer {
    // The user's own send first, since that is what they started.
    final going =
        [
          for (final t in _transfers.values)
            if (_fileState(t['state']).active) t,
        ]..sort(
          (a, b) =>
              (a['incoming'] == true ? 1 : 0) - (b['incoming'] == true ? 1 : 0),
        );
    final t = going.firstOrNull;
    if (t == null) return null;
    final id = t['id']! as String;
    final (size, done) = (t['size']! as int, t['done']! as int);
    final seen = _progress[id] ?? const [];
    var speed = 0;
    if (seen.length >= 2) {
      final ((t0, d0), (t1, d1)) = (seen.first, seen.last);
      if (t1 > t0) speed = ((d1 - d0) * 1000 ~/ (t1 - t0)).clamp(0, 1 << 40);
    }
    return Transfer(
      id: id,
      fileName: t['name']! as String,
      totalSize: formatBytes(size),
      sentSize: formatBytes(done),
      recipientId: t['with']! as String,
      percent: size == 0 ? 0 : (done * 100 ~/ size).clamp(0, 100),
      bytesPerSecond: speed,
      minutesLeft: speed > 0 ? ((size - done) / speed / 60).ceil() : null,
      incoming: t['incoming'] == true,
      paused: t['state'] == 'paused',
      transport: _transportTo(t['with']! as String),
      foundOver: _foundOver[t['with']! as String] ?? Transport.bluetooth,
    );
  }

  @override
  bool sendDirectPoll(String chatId, String question, List<String> options) {
    final choices = [
      for (final option in options)
        if (option.trim().isNotEmpty) option.trim(),
    ];
    if (question.trim().isEmpty || choices.length < 2) return false;
    final Object? envelope;
    try {
      envelope = _bridge.call({
        'op': 'send_text',
        'to': chatId,
        'body': question.trim(),
        'options': choices,
      });
    } on CoreException {
      return false;
    }
    _pump.deliver(envelope);
    _threads.remove(chatId);
    _lastActive[chatId] = _stamp();
    notifyListeners();
    return true;
  }

  @override
  void voteDirectPoll(String chatId, String messageId, int option) {
    final Object? envelope;
    try {
      envelope = _bridge.call({
        'op': 'vote',
        'with': chatId,
        'id': messageId,
        'choice': option,
      });
    } on CoreException {
      return;
    }
    _pump.deliver(envelope);
    _threads.remove(chatId);
    notifyListeners();
  }

  @override
  bool forwardText(String chatId, String text) {
    final body = text.trim();
    if (body.isEmpty || chatId == savedMessagesId) return false;
    final Object? envelope;
    try {
      // The core refuses unless this person accepted a chat request.
      envelope = _bridge.call({
        'op': 'send_text',
        'to': chatId,
        'body': body,
        'forwarded': true,
      });
    } on CoreException {
      return false;
    }
    _pump.deliver(envelope);
    _threads.remove(chatId);
    _lastActive[chatId] = _stamp();
    notifyListeners();
    return true;
  }

  MemberStatus _status = MemberStatus.online;

  String? _myAway;

  @override
  String? get myAway => _myAway;

  @override
  bool setAway(String? away) {
    final Object? reply;
    try {
      reply = _bridge.call({'op': 'set_away', 'away': away});
    } on CoreException {
      return false;
    }
    // Contacts are told when their devices can be reached.
    _pump.sendDeliveries(reply);
    _myAway = switch (reply) {
      {'away': final String said} => said,
      _ => null,
    };
    notifyListeners();
    return true;
  }

  @override
  MemberStatus get myStatus => _status;

  @override
  bool setMyStatus(MemberStatus status) {
    if (status == MemberStatus.offline) return false;
    final Object? reply;
    try {
      reply = _bridge.call({'op': 'set_status', 'status': status.wire});
    } on CoreException {
      return false;
    }
    // Fellow members in range are told, unless it is invisible.
    _pump.sendDeliveries(reply);
    _status = status;
    notifyListeners();
    return true;
  }

  @override
  bool sendDirectText(String chatId, String text) {
    final body = text.trim();
    if (body.isEmpty) return false;
    if (chatId == savedMessagesId) {
      try {
        _bridge.call({'op': 'save_note', 'body': body});
      } on CoreException {
        return false;
      }
      _saved = null;
      notifyListeners();
      return true;
    }
    final Object? envelope;
    try {
      // The core refuses unless this person accepted a chat request.
      envelope = _bridge.call({'op': 'send_text', 'to': chatId, 'body': body});
    } on CoreException {
      return false;
    }
    _trackRadio(chatId, _pump.deliverTracked(envelope));
    _threads.remove(chatId);
    _lastActive[chatId] = _stamp();
    notifyListeners();
    return true;
  }

  List<DirectItem> _notes() {
    try {
      final notes = _bridge.call({'op': 'notes'})! as List;
      return [
        for (final note in notes.cast<Map<String, Object?>>())
          DirectText(
            text: note['body']! as String,
            time: _clockTime(note['sent_at']! as int),
            mine: true,
            // A note is where it is going the moment it is written.
            delivered: true,
          ),
      ];
    } on CoreException {
      return const [];
    }
  }

  @override
  void markChatRead(String id) {
    if (!_messages(id).any((m) => !m.mine && !m.seen)) return;
    // The core tells the other person only if the user's "send read
    // receipts" switch is on. Otherwise this answers with nothing to send.
    _threads.remove(id);
    _act({'op': 'mark_read', 'with': id});
  }

  // Verification

  @override
  void startVerify(String id) {
    // One comparison at a time, whoever began it. And only with someone in
    // range: the words are worked out between the two devices, now.
    if (_comparing.contains(id) || !_inRange(id)) return;
    _act({'op': 'verify_start', 'with': id}, then: () => _comparing.add(id));
  }

  @override
  List<String>? verifyWords(String id) => _words[id];

  @override
  void confirmVerify(String id, {required bool matched}) {
    _act({'op': 'verify_confirm', 'with': id, 'matched': matched});
    _words.remove(id);
    _comparing.remove(id);
    notifyListeners();
  }
}

/// Someone the core has on record: a contact, or one side of a request.
class _Known {
  const _Known({
    required this.name,
    this.note,
    this.commonSpace,
    this.verified = false,
    this.timer = 0,
    this.hidden = false,
    this.verifiedBy,
    this.verifiedAt,
    this.away,
  });

  /// Why they said they are away, while they are.
  final String? away;

  /// The user deleted the chat with them; it is off the list until a new
  /// message comes.
  final bool hidden;

  /// How long messages in the chat with them live, in seconds.
  final int timer;
  final String name;
  final String? note;

  /// A space the user and this person are both in, if any.
  final String? commonSpace;
  final bool verified;

  /// How and when they were verified, where that was noted.
  final VerifyMethod? verifiedBy;
  final DateTime? verifiedAt;
}

/// A device that connected and proved which identity it holds.
class _Met {
  const _Met({required this.identity, this.name});
  final String identity;
  final String? name;
}

class _Message {
  const _Message({
    this.file,
    required this.mine,
    required this.body,
    required this.sentAt,
    required this.delivered,
    required this.read,
    required this.seen,
    this.id = '',
    this.options = const [],
    this.myVote,
    this.theirVote,
    this.goneAt,
    this.card,
    this.deleted = false,
    this.forwarded = false,
    this.location,
    this.sticker,
  });

  /// Deleted for everyone by whoever wrote it.
  final bool deleted;

  /// The sticker this message is, if it is one.
  final Sticker? sticker;

  /// Where the writer was, if that is what this message is.
  final Place? location;

  /// Passed on from a channel or another chat.
  final bool forwarded;

  /// A contact passed on: their name, identity and key.
  final (String, String, String)? card;

  /// When this message is to be deleted, in seconds since 1970.
  final int? goneAt;
  final String id;

  /// The choices, if this message is a poll.
  final List<String> options;
  final int? myVote;
  final int? theirVote;

  /// The transfer's id, if this message is a file.
  final String? file;
  final bool mine;
  final String body;
  final int sentAt;
  final bool delivered;
  final bool read;
  final bool seen;
}
