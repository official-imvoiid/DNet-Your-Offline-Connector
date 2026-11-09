import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/core_bridge.dart';
import 'lan_radio.dart';
import 'link_traffic.dart';
import 'lora/lora_radio.dart';
import 'radio.dart';

/// Carries frames between a radio and the core.
///
/// The radio says "a connection is up" and "here is a frame". The pump
/// passes both to the core and sends back whatever the core answers. It
/// reads nothing and decides nothing: who is at the other end, and what may
/// be said to them, is the core's business.
///
/// What it does decide is the order things go out on each connection.
/// Every link has its own queue, and what matters most goes first:
///
/// 1. the sound and picture of a call;
/// 2. chat: messages, receipts, call control, saying who is there;
/// 3. pieces of small files, under [smallFileBytes];
/// 4. pieces of big files.
///
/// A radio that says when frames have gone ([FramesSent]) is handed only a
/// few at a time, so a chat written while a file is moving goes out next,
/// between two frames of a piece: the core puts pieces on a lane of their
/// own, which the other side puts together apart from chat. A piece once
/// started is finished before another piece starts on the same link.
///
/// When Bluetooth and Wi-Fi both reach someone, the core sends chat on
/// both, and pieces on Wi-Fi. Pieces still waiting for Bluetooth are then
/// dropped here: the core sends them again on the faster link.
class LinkPump {
  LinkPump(this._bridge, this._radio) {
    _radio.onEvent = _onRadio;
  }

  final CoreBridge _bridge;
  final Radio _radio;

  final _eventListeners = <void Function(List<Map<String, Object?>>)>[];
  final _stateListeners = <void Function()>[];
  final _signalListeners = <void Function(int link, int rssi)>[];
  final _radioListeners = <void Function(RadioFrameOutcome outcome)>[];
  StreamSubscription<RadioFrameOutcome>? _radioOutcomes;

  /// Hears what became of each frame handed to a LoRa radio: sent,
  /// relayed, delivered or failed. The chat shows it beside the message.
  void onRadioOutcome(void Function(RadioFrameOutcome outcome) listener) {
    _radioListeners.add(listener);
    _listenToLora();
  }

  void _listenToLora() {
    final lora = this.lora;
    if (lora == null || _radioListeners.isEmpty) return;
    if (identical(_listenedLora, lora)) return;
    _radioOutcomes?.cancel();
    _listenedLora = lora;
    _radioOutcomes = lora.outcomes.listen((outcome) {
      for (final l in _radioListeners) {
        l(outcome);
      }
    });
  }

  LoRaRadio? _listenedLora;

  /// The LoRa radio, if this device has one plugged in.
  LoRaRadio? get lora {
    final radio = _radio;
    return radio is MultiRadio
        ? radio.lora
        : radio is LoRaRadio
        ? radio
        : null;
  }

  /// Puts a LoRa radio in beside Bluetooth and the network, or takes it
  /// out with null. Only a [MultiRadio] can take one.
  Future<void> setLora(LoRaRadio? lora) async {
    final radio = _radio;
    if (radio is! MultiRadio) return;
    await radio.setLora(lora);
    _listenToLora();
    _traffic.changed();
  }

  /// Takes frames of sound and picture during a call. They arrive only
  /// over a fast link, start with the byte `d7`, which no link frame
  /// does, and are already sealed with the call's key, so they skip the
  /// link's own handling and go straight to the call.
  void Function(int link, String frame)? onMedia;

  /// Sends one frame of a call on a fast link, ahead of everything else
  /// waiting there.
  void sendMedia(int link, String frame) {
    if (LinkNumbers.of(link) != Transport.wifi || !_open.contains(link)) return;
    final queue = _queue(link);
    // Sound that is late is no use: if the link is behind, the oldest
    // frames go unsent.
    while (queue.media.length >= _mostMedia) {
      queue.media.removeFirst();
    }
    queue.media.add(frame);
    _feed(link);
  }

  /// Hears how strongly each connected device is heard. The core is not
  /// told: it has no use for it.
  void onSignal(void Function(int link, int rssi) listener) =>
      _signalListeners.add(listener);

  /// Asks to be told what the core has to report: who came into range,
  /// what arrived, and so on.
  void onEvents(void Function(List<Map<String, Object?>> events) listener) =>
      _eventListeners.add(listener);

  /// Asks to be told when the radio starts or stops working.
  void onRadioState(void Function() listener) => _stateListeners.add(listener);

  void _radioStateChanged() {
    for (final listener in _stateListeners) {
      listener();
    }
  }

  /// How long a device that has connected gets to prove who it is. One
  /// that never does is using up a connection for nothing.
  static const _proofWait = Duration(seconds: 20);

  /// How many frames each kind of radio is handed before it says some
  /// have gone. Enough to keep it busy, few enough that a chat waits
  /// behind little. Wi-Fi frames are bigger and go many times faster. A
  /// LoRa radio is handed one at a time: the core puts a message back
  /// together in the order its frames arrive, and two frames in the air
  /// at once could arrive the other way round after a retry.
  static const _bluetoothWindow = 8;
  static const _networkWindow = 16;
  static const _radioWindow = 1;

  /// The most call frames kept waiting on one link.
  static const _mostMedia = 25;

  final Set<int> _open = {};

  /// How much each connection carries in a frame.
  final Map<int, int> _room = {};

  /// Who has proved they are at the other end of each connection.
  final Map<int, String> _peerOf = {};

  /// Connections still waiting for that proof.
  final Map<int, Timer> _unproved = {};
  bool _running = false;
  RadioState _state = RadioState.off;

  RadioState get state => _state;

  /// What is waiting on each connection.
  final Map<int, _Queue> _queues = {};

  /// Whether each kind of radio has said when frames have gone. One that
  /// has is from then on handed only a window at a time. A LoRa radio
  /// always does.
  bool _bluetoothReports = false;
  bool _networkReports = false;

  /// Connections being fed right now. A radio may hand back a frame while
  /// it is being given one, and the pump must not trip over itself.
  final Set<int> _feeding = {};

  /// Who each radio reaches, and what is waiting on each, as it changes.
  ValueListenable<LinkTraffic> get traffic => _traffic;
  late final _traffic = _TrafficWatch(this);

  /// Starts the radio. Does nothing if it is already running.
  void start() {
    if (_running) return;
    _running = true;
    _radio.start().catchError((Object _) {
      // A radio that cannot even be asked is one this device does not have.
      _onRadio(const RadioChanged(RadioState.unsupported));
    });
  }

  /// Switches the local network link on or off, where there is one.
  void useNetwork(bool on) {
    final radio = _radio;
    if (radio is MultiRadio) radio.useNetwork(on);
  }

  /// Switches the LoRa radio on or off, where there is one.
  Future<void> useLora(bool on) async {
    final radio = _radio;
    if (radio is MultiRadio) await radio.useLora(on);
  }

  /// Tells the radio where on a local network another DNet device is.
  void reach(String address) => _radio.reach(address);

  /// Stops the radio and forgets every connection.
  void stop() {
    if (!_running) return;
    _running = false;
    _radio.stop().catchError((Object _) {});
    for (final link in _open.toList()) {
      _close(link);
    }
    _state = RadioState.off;
    _drain();
    _radioStateChanged();
  }

  Future<bool> askPermission() => _radio.askPermission();

  /// Hands a sealed envelope to the device it is for. If that device is not
  /// connected the core keeps the envelope, still sealed, until it is.
  /// Returns true if it went out now.
  bool deliver(Object? envelope) => deliverTracked(envelope).sent;

  /// The same, saying which link carried it first and as what frames, so
  /// that what a LoRa radio reports of those frames can be matched to
  /// the message.
  Delivery deliverTracked(Object? envelope) {
    final reply =
        _bridge.call({'op': 'link_send', 'envelope': envelope})!
            as Map<String, Object?>;
    if (reply['delivered'] != true) {
      // Not in range. If it is something being kept until it arrives, the
      // core hands it to whoever is in range, to pass on.
      sendDeliveries(reply);
      return const Delivery(sent: false);
    }
    final link = reply['link']! as int;
    final frames = _frames(reply);
    _send(link, frames, _classOf(reply['class']));
    // The same, on every other link that reaches them.
    sendDeliveries(reply);
    return Delivery(sent: true, link: link, frames: frames);
  }

  /// Sends whatever a reply from the core asks to have sent to devices in
  /// range, each on the connection that reaches it.
  void sendDeliveries(Object? reply) {
    if (reply case {'deliveries': final List<Object?> deliveries}) {
      for (final delivery in deliveries) {
        if (delivery case {'link': final int link}) {
          _send(link, _frames(delivery), _classOf(delivery['class']));
        }
      }
    }
  }

  /// Looks for anything new the core has to report. Called after asking
  /// the core to do something that other parts of the app should hear of.
  void poll() => _drain();

  void _onRadio(RadioEvent event) {
    switch (event) {
      case LinkUp(:final link, :final maxFrame):
        if (!_running) return;
        final hello = _ask({
          'op': 'link_open',
          'link': link,
          'max_frame': maxFrame,
        });
        if (hello == null) return;
        _open.add(link);
        _room[link] = maxFrame;
        _unproved[link]?.cancel();
        _unproved[link] = Timer(_proofWait, () {
          _radio.drop(link);
          _close(link);
          _drain();
        });
        _send(link, hello, _Class.chat);
      case FrameIn(:final link, :final frame):
        // Anything can arrive over a radio. What the core will not take is
        // dropped here and goes no further.
        if (!_open.contains(link)) return;
        if (frame.startsWith('d7')) {
          // A call's sound or picture, many a second. Never over
          // Bluetooth, and nothing for the core's link to do.
          if (LinkNumbers.of(link) == Transport.wifi) {
            onMedia?.call(link, frame);
          }
          return;
        }
        final Object? reply;
        try {
          reply = _bridge.call({
            'op': 'link_receive',
            'link': link,
            'frame': frame,
          });
        } on CoreException {
          return;
        }
        final answer = _frames(reply);
        if (answer.isNotEmpty) _send(link, answer, _Class.chat);
        // A frame can also be news for other devices in range.
        sendDeliveries(reply);
      case FramesSent(:final link, :final count):
        switch (LinkNumbers.of(link)) {
          case Transport.wifi:
            _networkReports = true;
          case Transport.bluetooth:
            _bluetoothReports = true;
          case Transport.radio:
            break;
        }
        final queue = _queues[link];
        if (queue == null) return;
        queue.inRadio = (queue.inRadio - count).clamp(0, 1 << 30);
        _feed(link);
        return;
      case SignalSeen(:final link, :final rssi):
        if (!_open.contains(link)) return;
        for (final listener in _signalListeners) {
          listener(link, rssi);
        }
        return;
      case LinkDown(:final link):
        _close(link);
      case RadioChanged(:final state):
        if (!_running || state == _state) return;
        _state = state;
        _radioStateChanged();
        return;
    }
    _drain();
  }

  void _close(int link) {
    _unproved.remove(link)?.cancel();
    _room.remove(link);
    _peerOf.remove(link);
    // Whatever was waiting for this link goes with it. The core sends
    // again on another link anything that must arrive.
    _queues.remove(link);
    _traffic.changed();
    if (!_open.remove(link)) return;
    // If another connection still reaches the same device, the core asks
    // for what was lost with this one to be sent again on that.
    try {
      sendDeliveries(_bridge.call({'op': 'link_close', 'link': link}));
    } on CoreException {
      // Nothing is open any more, so there is nothing to send.
    }
  }

  /// Asks the core and returns the frames it wants sent, or null if it
  /// refused.
  List<String>? _ask(Map<String, Object?> request) {
    try {
      return _frames(_bridge.call(request));
    } on CoreException {
      return null;
    }
  }

  static List<String> _frames(Object? reply) => switch (reply) {
    {'frames': final List<Object?> frames} => frames.cast<String>(),
    _ => const [],
  };

  static _Class _classOf(Object? name) => switch (name) {
    'small' => _Class.small,
    'big' => _Class.big,
    _ => _Class.chat,
  };

  _Queue _queue(int link) => _queues.putIfAbsent(link, _Queue.new);

  /// Puts one message, as frames, in its place on a link's queue, and
  /// sends what there is room for.
  void _send(int link, List<String> frames, _Class kind) {
    if (frames.isEmpty || !_open.contains(link)) return;
    // A file piece is far too big for a LoRa radio: a megabyte at a
    // kilobit a second is hours of airtime. Files wait for another link.
    if (kind != _Class.chat && LinkNumbers.of(link) == Transport.radio) return;
    final queue = _queue(link);
    final unit = _Unit(frames, small: kind == _Class.small);
    switch (kind) {
      case _Class.chat:
        queue.chat.add(unit);
      case _Class.small:
        queue.small.add(unit);
      case _Class.big:
        queue.big.add(unit);
    }
    _feed(link);
  }

  bool _reports(int link) => switch (LinkNumbers.of(link)) {
    Transport.wifi => _networkReports,
    Transport.bluetooth => _bluetoothReports,
    Transport.radio => true,
  };

  int _window(int link) => switch (LinkNumbers.of(link)) {
    Transport.wifi => _networkWindow,
    Transport.bluetooth => _bluetoothWindow,
    Transport.radio => _radioWindow,
  };

  /// Hands the radio what fits on [link], most important first.
  void _feed(int link) {
    if (!_feeding.add(link)) return;
    try {
      while (true) {
        final queue = _queues[link];
        if (queue == null || !_open.contains(link)) break;
        final window = _reports(link) ? _window(link) : null;
        final batch = <String>[];
        while (window == null || queue.inRadio + batch.length < window) {
          final frame = queue.next();
          if (frame == null) break;
          batch.add(frame);
        }
        if (batch.isEmpty) break;
        queue.inRadio += batch.length;
        _traffic.changed();
        // May hand frames back in before it returns: whatever that queues
        // is picked up on the next turn of this loop.
        _radio.send(link, batch);
      }
    } finally {
      _feeding.remove(link);
    }
  }

  /// Someone has proved who they are on [link]. If a slower link also
  /// reaches them, the pieces of files still waiting there are dropped:
  /// the core has just sent them again on this one.
  void _proved(int link, String key) {
    _peerOf[link] = key;
    final room = _room[link] ?? 0;
    for (final MapEntry(key: other, value: who) in _peerOf.entries) {
      if (other == link || who != key || (_room[other] ?? 0) >= room) continue;
      final queue = _queues[other];
      if (queue == null) continue;
      queue.small.clear();
      queue.big.clear();
    }
    _traffic.changed();
  }

  void _drain() {
    final Object? events;
    try {
      events = _bridge.call({'op': 'poll'});
    } on CoreException {
      return;
    }
    if (events is! List || events.isEmpty) return;
    final happened = events.cast<Map<String, Object?>>();
    for (final event in happened) {
      if (event case {
        'kind': 'peer',
        'link': final int link,
        'key': final String key,
      }) {
        _unproved.remove(link)?.cancel();
        if (_open.contains(link)) _proved(link, key);
      }
    }
    for (final listener in _eventListeners) {
      listener(happened);
    }
  }

  LinkTraffic _measure() {
    final bluetooth = <String>{};
    final wifi = <String>{};
    final radio = <String>{};
    for (final MapEntry(key: link, value: key) in _peerOf.entries) {
      switch (LinkNumbers.of(link)) {
        case Transport.wifi:
          wifi.add(key);
        case Transport.bluetooth:
          bluetooth.add(key);
        case Transport.radio:
          radio.add(key);
      }
    }
    var onBluetooth = const LinkWaiting();
    var onWifi = const LinkWaiting();
    var onRadio = const LinkWaiting();
    for (final MapEntry(key: link, value: queue) in _queues.entries) {
      final waiting = queue.waiting();
      switch (LinkNumbers.of(link)) {
        case Transport.wifi:
          onWifi = _add(onWifi, waiting);
        case Transport.bluetooth:
          onBluetooth = _add(onBluetooth, waiting);
        case Transport.radio:
          onRadio = _add(onRadio, waiting);
      }
    }
    return LinkTraffic(
      bluetoothPeople: bluetooth.length,
      wifiPeople: wifi.length,
      radioPeople: radio.length,
      bluetooth: onBluetooth,
      wifi: onWifi,
      radio: onRadio,
    );
  }

  static LinkWaiting _add(LinkWaiting a, LinkWaiting b) => LinkWaiting(
    messages: a.messages + b.messages,
    smallBytes: a.smallBytes + b.smallBytes,
    bigBytes: a.bigBytes + b.bigBytes,
  );
}

/// What one delivery is, as the core says.
enum _Class { chat, small, big }

/// What became of handing an envelope over: whether it went out now,
/// and on which link, as which frames.
class Delivery {
  const Delivery({required this.sent, this.link, this.frames = const []});
  final bool sent;
  final int? link;
  final List<String> frames;

  /// The transport the first link is on, or null if it did not go.
  Transport? get transport => link == null ? null : LinkNumbers.of(link!);
}

/// One message as frames, and how many of them have been handed over.
class _Unit {
  _Unit(this.frames, {this.small = false});
  final List<String> frames;

  /// A piece of a small file.
  final bool small;
  int at = 0;

  bool get done => at >= frames.length;

  /// What is left, in bytes. Frames are hex.
  int get bytesLeft {
    var bytes = 0;
    for (var i = at; i < frames.length; i++) {
      bytes += frames[i].length ~/ 2;
    }
    return bytes;
  }
}

/// What is waiting on one link.
class _Queue {
  final media = Queue<String>();
  final chat = Queue<_Unit>();
  final small = Queue<_Unit>();
  final big = Queue<_Unit>();

  /// The piece being sent. Frames of two pieces must not be mixed on
  /// one link, so another starts only when this one is done.
  _Unit? bulk;

  /// Frames handed to the radio that it has not yet said have gone.
  int inRadio = 0;

  /// The next frame to hand over, or null if nothing is waiting.
  String? next() {
    if (media.isNotEmpty) return media.removeFirst();
    if (chat.isNotEmpty) {
      final unit = chat.first;
      final frame = unit.frames[unit.at++];
      if (unit.done) chat.removeFirst();
      return frame;
    }
    var unit = bulk;
    if (unit == null || unit.done) {
      unit = bulk = small.isNotEmpty
          ? small.removeFirst()
          : big.isNotEmpty
          ? big.removeFirst()
          : null;
      if (unit == null) return null;
    }
    final frame = unit.frames[unit.at++];
    if (unit.done) bulk = null;
    return frame;
  }

  LinkWaiting waiting() {
    var small = 0;
    var big = 0;
    for (final unit in this.small) {
      small += unit.bytesLeft;
    }
    for (final unit in this.big) {
      big += unit.bytesLeft;
    }
    if (bulk case final unit?) {
      if (unit.small) {
        small += unit.bytesLeft;
      } else {
        big += unit.bytesLeft;
      }
    }
    return LinkWaiting(messages: chat.length, smallBytes: small, bigBytes: big);
  }
}

/// [LinkPump.traffic]: worked out when asked, and passed on only when it
/// has changed.
class _TrafficWatch extends ChangeNotifier
    implements ValueListenable<LinkTraffic> {
  _TrafficWatch(this._pump);
  final LinkPump _pump;
  LinkTraffic _last = const LinkTraffic();

  @override
  LinkTraffic get value => _last = _pump._measure();

  void changed() {
    if (!hasListeners) return;
    final now = _pump._measure();
    if (now == _last) return;
    _last = now;
    notifyListeners();
  }
}
