import 'dart:async';
import 'dart:math';

import 'radio_transport.dart';

/// The air that mock radios share. Packets sent on it reach every other
/// mock radio on it, or only the ones it is told are in range of each
/// other, after a delay, sometimes lost, sometimes twice, sometimes out
/// of order: whatever the test asks for. Nothing real is involved.
///
/// It also stands in for a mesh: a radio that hears a packet not for it
/// passes it on to its own neighbours while the hop limit lasts, the way
/// Meshtastic floods, so a message can cross several radios.
class MockAir {
  MockAir({
    this.loss = 0,
    this.duplicate = 0,
    this.reorder = false,
    this.delay = Duration.zero,
    Random? random,
  }) : _random = random ?? Random(7);

  /// The share of packets that vanish, 0 to 1.
  double loss;

  /// The share of packets heard twice.
  double duplicate;

  /// Whether packets may arrive in another order than sent.
  bool reorder;

  /// The most a packet takes to arrive; each takes a random part of it.
  Duration delay;

  final Random _random;
  final Map<int, MockRadioDriver> _nodes = {};

  /// Who can hear whom. Empty: everyone hears everyone.
  final Map<int, Set<int>> _reach = {};

  /// Packets that were ever put on the air, for tests to look at.
  final List<RadioPacket> log = [];

  /// A test's say on which packets vanish, beyond [loss].
  bool Function(RadioPacket packet)? drop;

  /// Makes two radios able to hear each other, and nobody else unless
  /// also told. Once any pair is told, only told pairs hear each other.
  void link(int a, int b) {
    _reach.putIfAbsent(a, () => {}).add(b);
    _reach.putIfAbsent(b, () => {}).add(a);
  }

  void unlink(int a, int b) {
    _reach[a]?.remove(b);
    _reach[b]?.remove(a);
  }

  bool _hears(int listener, int speaker) =>
      _reach.isEmpty || (_reach[speaker]?.contains(listener) ?? false);

  void _join(MockRadioDriver node) => _nodes[node.node] = node;
  void _leave(MockRadioDriver node) => _nodes.remove(node.node);

  /// Puts a packet on the air from [from]. [relayedBy] is set when a
  /// radio in between is passing it on.
  void _transmit(RadioPacket packet, int from, {int? relayedBy}) {
    log.add(packet);
    final speaker = relayedBy ?? from;
    for (final node in _nodes.values.toList()) {
      if (node.node == speaker || node.node == from) continue;
      if (!node._on || !_hears(node.node, speaker)) continue;
      if (_random.nextDouble() < loss) continue;
      if (drop?.call(packet) ?? false) continue;
      final copies = _random.nextDouble() < duplicate ? 2 : 1;
      for (var c = 0; c < copies; c++) {
        final wait = reorder
            ? Duration(
                microseconds: _random.nextInt(max(delay.inMicroseconds, 1)),
              )
            : delay;
        Timer(wait, () {
          if (!node._on) return;
          node._hear(packet, from, speaker);
        });
      }
    }
  }

  /// Tells [from] what became of a packet it asked an answer for.
  void _report(int from, RadioDelivery delivery) {
    final node = _nodes[from];
    if (node == null || !node._on) return;
    Timer(delay, () => node._deliveries.add(delivery));
  }
}

/// A radio on a [MockAir]. Behaves like a Meshtastic node as far as the
/// protocol above can tell: addresses, hop limits, acknowledgements,
/// signal readings, and a connection that can be pulled.
class MockRadioDriver implements RadioTransport {
  MockRadioDriver(
    this.air, {
    required this.node,
    this.mtu = 200,
    this.bitsPerSecond = 1000,
    this.name = 'Mock',
    this.failConnect,
    this.rssi = -80,
    this.snr = 6.5,
    this.packetAirtime,
  });

  /// How long each packet is said to take on the air, for tests of what
  /// is worked out from it. Null: the mock does not say, as a radio that
  /// does not know its own settings would not.
  final Duration? packetAirtime;

  @override
  Duration? airtime(int bytes) => packetAirtime;

  final MockAir air;
  final int node;

  @override
  final int mtu;

  @override
  final int bitsPerSecond;
  final String name;

  /// Why connecting fails, if it is to.
  final RadioException? failConnect;

  /// How this radio is heard by others.
  int rssi;
  double snr;

  bool _on = false;
  RadioLinkStatus _status = const RadioLinkStatus(RadioLinkState.disconnected);
  RadioRegion? region;

  final _received = StreamController<RadioPacket>.broadcast();
  final _statuses = StreamController<RadioLinkStatus>.broadcast();
  final _signals = StreamController<RadioSignal>.broadcast();
  final _deliveries = StreamController<RadioDelivery>.broadcast();

  /// Packet ids seen, so a mesh copy coming round again is not passed on
  /// twice. Meshtastic keeps the same.
  final Set<int> _seen = {};

  void _setStatus(RadioLinkStatus status) {
    if (_status == status) return;
    _status = status;
    _statuses.add(status);
  }

  @override
  Future<void> connect() async {
    if (failConnect case final why?) {
      _setStatus(
        RadioLinkStatus(
          RadioLinkState.failed,
          reason: why.message,
          permanent: why.permanent,
        ),
      );
      throw why;
    }
    _setStatus(const RadioLinkStatus(RadioLinkState.connecting));
    _on = true;
    air._join(this);
    _setStatus(const RadioLinkStatus(RadioLinkState.connected));
  }

  @override
  Future<void> disconnect() async {
    _on = false;
    air._leave(this);
    _setStatus(const RadioLinkStatus(RadioLinkState.disconnected));
  }

  /// Pulls the cable: the device is gone, mid-send or not. The driver
  /// reports it is trying to get it back.
  void unplug() {
    _on = false;
    air._leave(this);
    _setStatus(const RadioLinkStatus(RadioLinkState.reconnecting));
  }

  /// Plugs it back in.
  void replug() {
    _on = true;
    air._join(this);
    _setStatus(const RadioLinkStatus(RadioLinkState.connected));
  }

  Future<void> dispose() async {
    await disconnect();
    await _received.close();
    await _statuses.close();
    await _signals.close();
    await _deliveries.close();
  }

  @override
  Future<void> send(RadioPacket packet) async {
    if (!_on) throw const RadioException('the radio is not connected');
    if (packet.data.length > mtu) {
      throw RadioException('a packet may be at most $mtu bytes');
    }
    final id = packet.id == 0 ? air._random.nextInt(0x7FFFFFFF) + 1 : packet.id;
    final sent = RadioPacket(
      to: packet.to,
      from: RadioAddress(node),
      data: packet.data,
      id: id,
      hopLimit: packet.hopLimit,
      wantAck: packet.wantAck,
      priority: packet.priority,
    );
    _seen.add(id);
    air._transmit(sent, node);
    if (packet.wantAck && !packet.to.isEveryone) {
      // Nobody answered within the air's delay, many times over: failed.
      Timer(air.delay * 8 + const Duration(milliseconds: 50), () {
        if (_acked.remove(id)) return;
        if (_on) _deliveries.add(RadioDelivery(id, RadioDeliveryState.failed));
      });
    }
  }

  /// Packets this radio asked an answer for that were answered.
  final Set<int> _acked = {};

  /// Hands this radio a packet as if it came off the air: for tests that
  /// play back what was recorded, or make up frames by hand. A packet
  /// with no id is given a fresh one, so it is not taken for a double.
  void receiveForTest(RadioPacket packet) {
    if (!_on) return;
    final id = packet.id == 0 ? air._random.nextInt(0x7FFFFFFF) + 1 : packet.id;
    // The mock drops doubles as a mesh node does; a test replaying a
    // recording wants the protocol above to do the dropping.
    _seen.remove(id);
    _hear(
      RadioPacket(
        to: packet.to,
        from: packet.from ?? const RadioAddress(0),
        data: packet.data,
        id: id,
        hopLimit: packet.hopLimit,
        wantAck: packet.wantAck,
        rssi: packet.rssi,
        snr: packet.snr,
        hopsTravelled: packet.hopsTravelled,
      ),
      packet.from?.node ?? 0,
      packet.from?.node ?? 0,
    );
  }

  void _hear(RadioPacket packet, int from, int speaker) {
    if (!_seen.add(packet.id)) {
      // Heard already, by another way round. Meshtastic drops these too.
      return;
    }
    final mine = packet.to.node == node || packet.to.isEveryone;
    final hops = (packet.hopsTravelled ?? 0) + (speaker == from ? 0 : 1);
    if (mine) {
      final heard = RadioPacket(
        to: packet.to,
        from: packet.from,
        data: packet.data,
        id: packet.id,
        hopLimit: packet.hopLimit,
        wantAck: packet.wantAck,
        rssi: air._nodes[speaker]?.rssi ?? rssi,
        snr: air._nodes[speaker]?.snr ?? snr,
        hopsTravelled: hops,
      );
      _signals.add(
        RadioSignal(from: packet.from!, rssi: heard.rssi, snr: heard.snr),
      );
      _received.add(heard);
      if (packet.wantAck && packet.to.node == node) {
        air._nodes[from]?._acked.add(packet.id);
        air._report(
          from,
          RadioDelivery(packet.id, RadioDeliveryState.delivered),
        );
      }
    }
    if (!packet.to.isEveryone && mine) return;
    // Pass it on, as a mesh node does, while the hops last.
    if (packet.hopLimit <= 0) return;
    final onward = RadioPacket(
      to: packet.to,
      from: packet.from,
      data: packet.data,
      id: packet.id,
      hopLimit: packet.hopLimit - 1,
      wantAck: packet.wantAck,
      priority: packet.priority,
      hopsTravelled: hops + 1,
    );
    if (packet.wantAck && !packet.to.isEveryone) {
      air._report(from, RadioDelivery(packet.id, RadioDeliveryState.relayed));
    }
    air._transmit(onward, from, relayedBy: node);
  }

  @override
  Stream<RadioPacket> get received => _received.stream;

  @override
  Stream<RadioLinkStatus> get status => Stream.multi((listener) {
    // The state now, then every change, from the moment of listening:
    // nothing that happens in between is missed.
    listener.add(_status);
    final sub = _statuses.stream.listen(listener.add, onDone: listener.close);
    listener.onCancel = sub.cancel;
  });

  @override
  RadioLinkStatus get linkStatus => _status;

  @override
  Stream<RadioSignal> get signals => _signals.stream;

  @override
  Stream<RadioDelivery> get deliveries => _deliveries.stream;

  @override
  RadioDeviceInfo? get device => _on
      ? RadioDeviceInfo(
          kind: RadioDriverKind.mock,
          name: name,
          hardware: 'mock',
          firmware: 'mock',
          address: RadioAddress(node),
          region: region?.code,
          preset: 'LONG_FAST',
        )
      : null;

  @override
  RadioAddress? get myAddress => RadioAddress(node);

  @override
  Future<void> setRegion(RadioRegion region) async {
    if (!_on) throw const RadioException('the radio is not connected');
    this.region = region;
  }
}
