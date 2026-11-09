import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../channel_radio.dart' show hexDecode, hexEncode;
import '../radio.dart';
import 'radio_protocol.dart';
import 'radio_transport.dart';

/// A LoRa radio as the link pump sees it: one more [Radio], beside
/// Bluetooth and the local network, that finds devices and carries
/// frames. The core's link protocol (hello, proof, sealed envelopes) runs
/// over it unchanged, so a person reached only by radio is proved and
/// sealed to exactly as over Bluetooth.
///
/// Each DNet device heard on the radio gets a link of its own, numbered
/// from [LinkNumbers.radio]. A device is heard by its beacon (a few bytes
/// every couple of minutes saying "DNet is here") or by any frame it
/// sends; one not heard for [quietFor] is dropped. Frames go through
/// [RadioProtocol], which fragments, acknowledges and retries them.
///
/// Frames on the radio are small: the core is told [maxFrame] bytes, as
/// much as one packet of this radio carries after the protocol's header,
/// so every core frame is one radio packet. Fewer, fuller packets cost
/// less airtime than more, smaller ones: each pays for a preamble and a
/// header, and each is answered by an ACK.
///
/// Every frame carries a tag naming the sender's link it belongs to. The
/// core's handshake sends its hello once, and a link takes one hello, so
/// a frame of an old link must never reach a new one: one landing in the
/// middle of a hello would leave the new link unproved on both sides. A
/// frame tagged for a link that has ended here is dropped; a frame with
/// a tag not seen before means the other end began a new link, and the
/// old one is closed here too. Closing a link also stops the protocol
/// retrying what was in flight on it.
///
/// Files never go this way: the pump drops file pieces on radio links.
class LoRaRadio extends Radio {
  LoRaRadio(
    this.transport, {
    RadioProtocolConfig config = const RadioProtocolConfig(),
    this.beaconEvery = const Duration(minutes: 2),
    this.quietFor = const Duration(minutes: 12),
    this.region,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    protocol = RadioProtocol(
      transport,
      config: RadioProtocolConfig(
        tries: config.tries,
        firstWait: config.firstWait,
        minWait: config.minWait,
        mostWait: config.mostWait,
        hopLimit: config.hopLimit,
        compress: config.compress,
        reassemblyLife: config.reassemblyLife,
        mostAssembling: config.mostAssembling,
        mostMessage: config.mostMessage,
        dedupeWindow: config.dedupeWindow,
        dutyCycle: region?.dutyCycle ?? config.dutyCycle,
        airtimeWindow: config.airtimeWindow,
        reliable: config.reliable,
      ),
      clock: clock,
    );
  }

  final RadioTransport transport;
  late final RadioProtocol protocol;
  final Duration beaconEvery;
  final Duration quietFor;

  /// The band the user chose, if they have. The radio is set to it on
  /// start, and its duty cycle bounds what is sent.
  final RadioRegion? region;
  final DateTime Function() _clock;

  /// The most bytes one core frame may carry here: one packet of this
  /// radio less the protocol's header and the link's tag, so a frame is
  /// one packet (201 on a Meshtastic device).
  int get maxFrame => (transport.mtu - RadioFrame.dataHeader - frameHeader)
      .clamp(minFrame, mostFrame);

  /// A core frame on the radio: [frameKind], the tag of the sender's link
  /// (4 bytes), then the frame.
  static const frameKind = 0xD2;
  static const frameHeader = 5;

  /// The core's smallest frame, and a cap well past any LoRa packet.
  static const minFrame = 20;
  static const mostFrame = 1024;

  /// Past this share of the airtime budget, the regular "DNet is here"
  /// stands aside for chat. Asked for by hand ([announce]) it still goes.
  static const beaconBudget = 0.5;

  /// What a beacon says: "DNet", the protocol version, and two bytes
  /// that change each time this radio comes up. A device that hears a
  /// known node with new bytes knows its old link to it is dead, and
  /// opens a fresh one: the other end has forgotten the handshake.
  static const beaconMagic = [0x44, 0x4E, 0x65, 0x74];

  /// 2: frames carry their link's tag. A device on 1 (DNet 0.2.0) is not
  /// heard, rather than heard wrongly.
  static const beaconVersion = 2;
  static const beaconLength = 7;
  int _bootId = 0;
  final Map<RadioAddress, int> _bootOf = {};

  bool _running = false;
  Timer? _beacon;
  Timer? _sweep;
  final List<StreamSubscription<Object?>> _listening = [];
  int _nextLink = LinkNumbers.radio;

  /// Each DNet device heard, by node: its link number and when last heard.
  final Map<RadioAddress, int> _linkOf = {};
  final Map<int, RadioAddress> _nodeOf = {};
  final Map<int, DateTime> _lastHeard = {};

  /// Nodes dropped on purpose, left alone until this time.
  final Map<RadioAddress, DateTime> _shunned = {};

  /// The tag this device puts on the frames of each of its links, and the
  /// tag of the other end's link that each is joined to, once heard.
  final Map<int, int> _myTag = {};
  final Map<int, int> _theirTag = {};

  /// The other end's tags of links that have ended here, lately, by node:
  /// a frame still carrying one is from the past.
  final Map<RadioAddress, List<int>> _ended = {};
  final _tags = Random.secure();

  /// Whether the device has been up since [start]: only coming back
  /// after that is a new start for the others.
  bool _wasUp = false;
  static const _shunFor = Duration(minutes: 5);

  /// Frames being sent on each link, by their first bytes as hex, and
  /// what became of each: for the per-message status the chat shows.
  final _outcomes = StreamController<RadioFrameOutcome>.broadcast();

  /// What became of each frame handed to [send].
  Stream<RadioFrameOutcome> get outcomes => _outcomes.stream;

  /// For the status screen: how the link is, how the last device was
  /// heard, and counts.
  final ValueNotifier<RadioStats> stats = ValueNotifier(const RadioStats());

  /// The link for each node heard, for the status screen.
  Map<RadioAddress, int> get links => Map.unmodifiable(_linkOf);

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _wasUp = false;
    _bootId = Random.secure().nextInt(0x10000);
    _listening.add(transport.status.listen(_onStatus));
    _listening.add(protocol.messages.listen(_onMessage));
    _listening.add(transport.signals.listen(_onSignal));
    _listening.add(protocol.states.listen(_onState));
    protocol.start();
    try {
      await transport.connect();
    } on RadioException catch (e) {
      // The status stream has said why. A permanent failure is one this
      // device cannot fix; the app shows it as no radio.
      onEvent?.call(
        RadioChanged(e.permanent ? RadioState.unsupported : RadioState.off),
      );
      return;
    }
    if (region case final region?) {
      try {
        await transport.setRegion(region);
      } on RadioException {
        // The device keeps its own setting. The screen shows which.
      }
    }
    _beacon = Timer.periodic(beaconEvery, (_) => _sayHere(regular: true));
    _sweep = Timer.periodic(const Duration(seconds: 30), (_) => _dropQuiet());
    _sayHere();
    _refreshStats();
  }

  /// Says "DNet is here" now, whatever the budget: the radio screen's
  /// link test. Devices that hear it answer with their own and get a
  /// link. False if the radio is not up.
  bool announce() {
    if (!_running || !transport.linkStatus.isUp) return false;
    _sayHere();
    stats.value = stats.value.copyWith(announcedAt: _clock());
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _beacon?.cancel();
    _beacon = null;
    _sweep?.cancel();
    _sweep = null;
    for (final link in _nodeOf.keys.toList()) {
      _close(link);
    }
    for (final sub in _listening) {
      unawaited(sub.cancel());
    }
    _listening.clear();
    await protocol.stop();
    await transport.disconnect();
    onEvent?.call(const RadioChanged(RadioState.off));
    _refreshStats();
  }

  Future<void> dispose() async {
    await stop();
    await protocol.dispose();
    await _outcomes.close();
    stats.dispose();
  }

  void _onStatus(RadioLinkStatus status) {
    if (!_running) return;
    switch (status.state) {
      case RadioLinkState.connected:
        onEvent?.call(const RadioChanged(RadioState.on));
        // Back after going away: fresh bytes, so the others close the
        // links they had and open fresh ones. Here for the first time:
        // the bytes [start] chose, or the others would open a link and
        // close it again at once.
        if (_wasUp) _bootId = Random.secure().nextInt(0x10000);
        _wasUp = true;
        _sayHere();
      case RadioLinkState.failed:
        onEvent?.call(
          RadioChanged(
            status.permanent ? RadioState.unsupported : RadioState.off,
          ),
        );
      case RadioLinkState.reconnecting || RadioLinkState.disconnected:
        // Every link is gone with the device. Each comes back when the
        // device does and the node is heard again.
        for (final link in _nodeOf.keys.toList()) {
          _close(link);
        }
      case RadioLinkState.connecting:
        break;
    }
    _refreshStats();
  }

  void _sayHere({bool regular = false}) {
    if (!transport.linkStatus.isUp) return;
    // On a band with a duty cycle, airtime is the law's to ration: when
    // half the hour's share is spent, presence waits and chat goes.
    final duty = protocol.config.dutyCycle;
    if (regular &&
        duty != null &&
        duty > 0 &&
        protocol.budget.used / duty > beaconBudget) {
      return;
    }
    try {
      protocol.send(
        RadioAddress.everyone,
        Uint8List.fromList([
          ...beaconMagic,
          beaconVersion,
          _bootId >> 8,
          _bootId & 0xFF,
        ]),
        priority: RadioPriority.background,
      );
    } on Object {
      // A radio with no room, or none at all. The next beacon may do.
    }
  }

  static bool _isBeacon(Uint8List data) =>
      data.length == beaconLength &&
      data[0] == beaconMagic[0] &&
      data[1] == beaconMagic[1] &&
      data[2] == beaconMagic[2] &&
      data[3] == beaconMagic[3] &&
      data[4] == beaconVersion;

  /// The most DNet radios linked at once, and how fast new ones are taken
  /// on. Anyone with a radio on the channel can make up node numbers, and
  /// each new link costs this device airtime saying who it is: without a
  /// limit, beacons from made-up nodes would spend the band's airtime, and
  /// on a band with a duty cycle the law's share of it, on nobody. A crowd
  /// arriving at once still gets in: [newLinksAtOnce] together, then one
  /// more every [newLinkEvery].
  static const mostLinks = 32;
  static const newLinksAtOnce = 8;
  static const newLinkEvery = Duration(seconds: 10);
  double _newLinks = newLinksAtOnce.toDouble();
  DateTime? _newLinksAt;

  /// The most nodes left alone at once; see [drop].
  static const mostShunned = 1024;

  bool _mayLinkNew() {
    if (_linkOf.length >= mostLinks) return false;
    final now = _clock();
    final since = now.difference(_newLinksAt ?? now).inMilliseconds;
    _newLinksAt = now;
    _newLinks = min(
      newLinksAtOnce.toDouble(),
      _newLinks + max(0, since) / newLinkEvery.inMilliseconds,
    );
    if (_newLinks < 1) return false;
    _newLinks -= 1;
    return true;
  }

  /// A device was heard. Gives it a link if it has none, unless it was
  /// dropped on purpose lately.
  int? _heard(RadioAddress node) {
    final until = _shunned[node];
    if (until != null) {
      if (_clock().isBefore(until)) return null;
      _shunned.remove(node);
    }
    final known = _linkOf[node];
    if (known != null) {
      _lastHeard[known] = _clock();
      return known;
    }
    if (!_mayLinkNew()) return null;
    final link = _nextLink++;
    _linkOf[node] = link;
    _nodeOf[link] = node;
    _lastHeard[link] = _clock();
    _myTag[link] = _tags.nextInt(0xFFFFFFFF) + 1;
    // A beacon from someone new means they may not have heard ours yet:
    // answer at once rather than in up to two minutes.
    _answerNewcomer();
    onEvent?.call(LinkUp(link, maxFrame));
    _refreshStats();
    return link;
  }

  /// When the last answer to a newcomer went, so a crowd arriving at
  /// once is answered once.
  DateTime? _answeredAt;

  void _answerNewcomer() {
    final now = _clock();
    final last = _answeredAt;
    if (last != null && now.difference(last) < beaconEvery ~/ 4) return;
    _answeredAt = now;
    _sayHere(regular: true);
  }

  void _onMessage(RadioMessage message) {
    if (!_running) return;
    stats.value = stats.value.copyWith(
      received: stats.value.received + 1,
      lastHops: message.hopsTravelled,
      lastHeardAt: _clock(),
    );
    if (_isBeacon(message.data)) {
      final boot = (message.data[5] << 8) | message.data[6];
      final before = _bootOf[message.from];
      if (before != null && before != boot) {
        // Their radio came back: whatever link there was is dead at
        // their end.
        final old = _linkOf[message.from];
        if (old != null) _close(old);
      }
      if (_bootOf.length >= 1024 && !_bootOf.containsKey(message.from)) {
        _bootOf.remove(_bootOf.keys.first);
      }
      _bootOf[message.from] = boot;
      _heard(message.from);
      return;
    }
    final data = message.data;
    if (data.length <= frameHeader || data[0] != frameKind) return;
    final tag = ByteData.sublistView(data).getUint32(1);
    final ended = _ended[message.from]?.contains(tag) ?? false;
    final known = _linkOf[message.from];
    if (known != null) {
      final theirs = _theirTag[known];
      if (theirs != null && theirs != tag) {
        // A frame of a link that ended here: from the past.
        if (ended) return;
        // A link they have just begun: the one before is dead at their
        // end, and its handshake cannot be had again on it.
        _close(known);
      }
    }
    final link = _heard(message.from);
    if (link == null) return;
    // From a link that ended here, and nothing of it belongs in this one.
    // They may not know it ended; this link's own frames, with a tag new
    // to them, will tell them.
    if (ended) return;
    _theirTag[link] ??= tag;
    onEvent?.call(
      FrameIn(link, hexEncode(Uint8List.sublistView(data, frameHeader))),
    );
  }

  void _onSignal(RadioSignal signal) {
    if (!_running) return;
    final link = _linkOf[signal.from];
    final rssi = signal.rssi;
    if (link != null && rssi != null) onEvent?.call(SignalSeen(link, rssi));
    stats.value = stats.value.copyWith(lastSignal: signal);
  }

  void _dropQuiet() {
    final now = _clock();
    for (final MapEntry(key: link, value: at) in _lastHeard.entries.toList()) {
      if (now.difference(at) > quietFor) _close(link);
    }
  }

  void _close(int link) {
    final node = _nodeOf.remove(link);
    if (node == null) return;
    _linkOf.remove(node);
    _lastHeard.remove(link);
    _myTag.remove(link);
    if (_theirTag.remove(link) case final theirs?) {
      final ended = _ended.putIfAbsent(node, () => []);
      ended.add(theirs);
      if (ended.length > 8) ended.removeAt(0);
      if (_ended.length > 256) _ended.remove(_ended.keys.first);
    }
    // What is in the air for it stops: a retry arriving later would land
    // in whatever link replaced it at the other end.
    for (final MapEntry(key: id, value: (on, frame))
        in _sends.entries.toList()) {
      if (on != link) continue;
      _sends.remove(id);
      protocol.cancel(id);
      _outcomes.add(RadioFrameOutcome(link, frame, RadioSendState.failed));
    }
    // Whatever was waiting for this link goes with it: the core sends
    // again on another link anything that must arrive.
    for (final frame in _waiting.remove(link) ?? const <String>[]) {
      _outcomes.add(RadioFrameOutcome(link, frame, RadioSendState.failed));
    }
    _inFlight.remove(link);
    onEvent?.call(LinkDown(link));
    _refreshStats();
  }

  /// Frames waiting on each link, and whether one is in the air. One
  /// frame at a time per link: the core puts a message together in the
  /// order its frames arrive, so they must not overtake each other.
  final Map<int, Queue<String>> _waiting = {};
  final Set<int> _inFlight = {};

  @override
  void send(int link, List<String> frames) {
    if (!_nodeOf.containsKey(link) || frames.isEmpty) return;
    _waiting.putIfAbsent(link, Queue.new).addAll(frames);
    _next(link);
  }

  /// Sends the next frame waiting on [link], if none is in the air.
  void _next(int link) {
    if (_inFlight.contains(link)) return;
    final node = _nodeOf[link];
    final queue = _waiting[link];
    if (node == null || queue == null || queue.isEmpty) return;
    final frame = queue.removeFirst();
    final RadioSend sending;
    try {
      final body = hexDecode(frame);
      final tagged = Uint8List(frameHeader + body.length)
        ..[0] = frameKind
        ..setRange(frameHeader, frameHeader + body.length, body);
      ByteData.sublistView(tagged).setUint32(1, _myTag[link]!);
      sending = protocol.send(node, tagged);
    } on Object {
      _outcomes.add(RadioFrameOutcome(link, frame, RadioSendState.failed));
      stats.value = stats.value.copyWith(failed: stats.value.failed + 1);
      onEvent?.call(FramesSent(link, 1));
      _next(link);
      return;
    }
    _inFlight.add(link);
    _sends[sending.id] = (link, frame);
    _outcomes.add(RadioFrameOutcome(link, frame, RadioSendState.sent));
    stats.value = stats.value.copyWith(sent: stats.value.sent + 1);
  }

  /// The link and frame behind each protocol send, to report on.
  final Map<int, (int, String)> _sends = {};

  void _onState((RadioSend, RadioSendState) change) {
    final (send, state) = change;
    final known = _sends[send.id];
    if (known == null) return;
    final (link, frame) = known;
    _outcomes.add(RadioFrameOutcome(link, frame, state));
    if (state == RadioSendState.delivered || state == RadioSendState.failed) {
      _sends.remove(send.id);
      _inFlight.remove(link);
      // One more frame has left the queue, whatever became of it.
      onEvent?.call(FramesSent(link, 1));
      if (state == RadioSendState.failed) {
        stats.value = stats.value.copyWith(
          failed: stats.value.failed + 1,
          lastProblem: send.reason,
        );
      } else {
        stats.value = stats.value.copyWith(
          delivered: stats.value.delivered + 1,
          roundTrip: protocol.roundTrip(send.to),
        );
      }
      _next(link);
    }
    _refreshStats();
  }

  @override
  void drop(int link) {
    final node = _nodeOf[link];
    if (node != null) {
      if (_shunned.length >= mostShunned) {
        final now = _clock();
        _shunned.removeWhere((_, until) => !now.isBefore(until));
        // Still full: the one left alone longest goes first.
        if (_shunned.length >= mostShunned) {
          _shunned.remove(_shunned.keys.first);
        }
      }
      _shunned[node] = _clock().add(_shunFor);
    }
    _close(link);
  }

  @override
  Future<bool> askPermission() async {
    // A radio needs no question of the user beyond plugging it in; the
    // platform asks about USB and Bluetooth when the link is opened.
    return transport.linkStatus.isUp;
  }

  void _refreshStats() {
    stats.value = stats.value.copyWith(
      status: transport.linkStatus,
      device: transport.device,
      peers: _linkOf.length,
      airtimeUsed: protocol.budget.used,
      dutyCycle: protocol.config.dutyCycle,
    );
  }
}

/// What became of one frame handed to the radio.
class RadioFrameOutcome {
  const RadioFrameOutcome(this.link, this.frame, this.state);
  final int link;

  /// The frame as it was handed over, hex.
  final String frame;
  final RadioSendState state;
}

/// What the Radio screen shows.
@immutable
class RadioStats {
  const RadioStats({
    this.status = const RadioLinkStatus(RadioLinkState.disconnected),
    this.device,
    this.peers = 0,
    this.sent = 0,
    this.received = 0,
    this.delivered = 0,
    this.failed = 0,
    this.lastSignal,
    this.lastHops,
    this.airtimeUsed = 0,
    this.dutyCycle,
    this.lastHeardAt,
    this.lastProblem,
    this.roundTrip,
    this.announcedAt,
  });

  final RadioLinkStatus status;
  final RadioDeviceInfo? device;

  /// DNet devices heard lately.
  final int peers;
  final int sent;
  final int received;
  final int delivered;
  final int failed;
  final RadioSignal? lastSignal;
  final int? lastHops;

  /// The share of the airtime window spent, 0 to 1.
  final double airtimeUsed;

  /// The band's duty cycle, where it has one: the share [airtimeUsed]
  /// counts against.
  final double? dutyCycle;

  /// When a DNet device was last heard.
  final DateTime? lastHeardAt;

  /// Why the last frame failed, in plain words.
  final String? lastProblem;

  /// The last timed round trip: a frame out, its ACK back.
  final Duration? roundTrip;

  /// When "DNet is here" was last sent by hand.
  final DateTime? announcedAt;

  RadioStats copyWith({
    RadioLinkStatus? status,
    RadioDeviceInfo? device,
    int? peers,
    int? sent,
    int? received,
    int? delivered,
    int? failed,
    RadioSignal? lastSignal,
    int? lastHops,
    double? airtimeUsed,
    double? dutyCycle,
    DateTime? lastHeardAt,
    String? lastProblem,
    Duration? roundTrip,
    DateTime? announcedAt,
  }) => RadioStats(
    status: status ?? this.status,
    device: device ?? this.device,
    peers: peers ?? this.peers,
    sent: sent ?? this.sent,
    received: received ?? this.received,
    delivered: delivered ?? this.delivered,
    failed: failed ?? this.failed,
    lastSignal: lastSignal ?? this.lastSignal,
    lastHops: lastHops ?? this.lastHops,
    airtimeUsed: airtimeUsed ?? this.airtimeUsed,
    dutyCycle: dutyCycle ?? this.dutyCycle,
    lastHeardAt: lastHeardAt ?? this.lastHeardAt,
    lastProblem: lastProblem ?? this.lastProblem,
    roundTrip: roundTrip ?? this.roundTrip,
    announcedAt: announcedAt ?? this.announcedAt,
  );
}
