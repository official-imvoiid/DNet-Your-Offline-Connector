import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'byte_link.dart';
import 'meshtastic_proto.dart';
import 'radio_transport.dart';

/// A Meshtastic device, by whichever of its three connections: USB
/// serial, TCP over Wi-Fi, or Bluetooth LE. All three carry the same
/// protobuf messages (`ToRadio` and `FromRadio`); serial and TCP wrap
/// each in the stream framing, and BLE hands them over whole, one per
/// characteristic write or read. The [ByteLink] it is given takes care
/// of the bytes; this driver takes care of the conversation:
///
/// 1. On connect over serial or TCP, send 32 wake bytes, as the official
///    clients do, then ask for the device's configuration
///    (`want_config_id`) and read what comes back until
///    `config_complete_id` says that is all: the device's own node
///    number, the nodes it knows, the LoRa settings (region, preset) and
///    the firmware.
/// 2. Send the app's packets on port [PortNum.dnet], to one node or to
///    everyone, with the hop limit and priority asked for, and `want_ack`
///    where asked, but only while the device's send queue has room: it
///    answers every packet with a `QueueStatus`, and a packet handed to a
///    full queue is dropped.
/// 3. Hand up every packet heard on that port, with its signal readings.
/// 4. Turn what the device says back into [RadioDelivery] reports:
///    acknowledged by the node it was for (delivered), by a node in
///    between (relayed), or refused, with the reason in plain words
///    (failed). Refusals come for any packet: the duty-cycle limit, a full
///    queue, a packet too large.
/// 5. Send a heartbeat now and then, so the device keeps the link open.
///
/// The device's own encryption (the channel key) is treated as nothing:
/// every packet the app hands it is a sealed core envelope or a frame
/// of the app's own protocol, both of which prove and hide what they
/// carry on their own.
///
/// Not yet tried with a real device. Checked against a stand-in that
/// speaks the same bytes (see meshtastic_driver_test.dart).
class MeshtasticDriver implements RadioTransport {
  MeshtasticDriver(
    this.link, {
    this.heartbeatEvery = const Duration(seconds: 60),
    this.configTimeout = const Duration(seconds: 15),
    this.reconnectEvery = const Duration(seconds: 5),
    this.queueWait = const Duration(seconds: 30),
    this.rebootSettle = const Duration(seconds: 8),
    this.reconnect = true,
    Random? random,
  }) : _random = random ?? Random.secure();

  final ByteLink link;
  final Duration heartbeatEvery;
  final Duration configTimeout;
  final Duration reconnectEvery;

  /// How long a packet waits for room in the device's send queue before
  /// it is given up on.
  final Duration queueWait;

  /// How long after a settings change (which reboots the device) to ask
  /// for its configuration again, for links that stay open across the
  /// reboot (a USB bridge chip keeps the port while the radio restarts).
  final Duration rebootSettle;

  /// Whether to keep trying when the device goes away.
  final bool reconnect;
  final Random _random;

  final _received = StreamController<RadioPacket>.broadcast();
  final _statuses = StreamController<RadioLinkStatus>.broadcast();
  final _signals = StreamController<RadioSignal>.broadcast();
  final _deliveries = StreamController<RadioDelivery>.broadcast();
  final _framer = StreamFramer();

  RadioLinkStatus _status = const RadioLinkStatus(RadioLinkState.disconnected);
  StreamSubscription<Uint8List>? _reading;
  Timer? _heartbeat;
  Timer? _reconnecting;
  Timer? _refreshing;
  Completer<void>? _configured;
  int _configId = 0;
  bool _wanted = false;

  int? _myNode;
  MeshLoraConfig? _lora;
  MeshMetadata? _metadata;
  MeshUser? _me;

  /// The last thing the device asked the user be told, if any.
  String? _notice;

  /// The nodes the device knows, by number.
  final Map<int, MeshNodeInfo> nodes = {};

  /// Every packet handed to the device lately, by id, and the node it was
  /// for: to match what the device says about it.
  final Map<int, int> _ours = {};

  /// Of those, the ids sent with `want_ack`, still waiting for word.
  final Set<int> _awaiting = {};

  /// Packets heard already, by id: the device may hand the same one up
  /// twice when it hears it by two paths.
  final Set<int> _heard = {};

  /// Room left in the device's send queue, as it last said less what has
  /// been handed to it since. Null until it says.
  int? _queueFree;
  final List<Completer<void>> _roomWaiters = [];

  void _setStatus(RadioLinkStatus status) {
    if (_status == status) return;
    _status = status;
    _statuses.add(status);
  }

  @override
  RadioLinkStatus get linkStatus => _status;

  @override
  Stream<RadioLinkStatus> get status => Stream.multi((listener) {
    // The state now, then every change, from the moment of listening:
    // nothing that happens in between is missed.
    listener.add(_status);
    final sub = _statuses.stream.listen(listener.add, onDone: listener.close);
    listener.onCancel = sub.cancel;
  });

  @override
  Stream<RadioPacket> get received => _received.stream;

  @override
  Stream<RadioSignal> get signals => _signals.stream;

  @override
  Stream<RadioDelivery> get deliveries => _deliveries.stream;

  @override
  RadioAddress? get myAddress =>
      _myNode == null ? null : RadioAddress(_myNode!);

  /// What fits one packet in every case: 255 bytes a LoRa packet, less the
  /// firmware's header, public-key encryption and the `Data` tags, is 219
  /// ([MeshLimits.appPayload]); 212 keeps a few bytes spare for a field a
  /// newer firmware may add.
  @override
  int get mtu => 212;

  @override
  int? get bitsPerSecond => _lora?.modem?.bitsPerSecond;

  @override
  Duration? airtime(int bytes) => _lora?.modem?.airtime(
    bytes +
        MeshLimits.header +
        MeshLimits.dataOverhead +
        MeshLimits.pkcOverhead,
  );

  @override
  RadioDeviceInfo? get device {
    if (_myNode == null) return null;
    final hw = _metadata?.hwModel;
    final lora = _lora;
    return RadioDeviceInfo(
      kind: RadioDriverKind.meshtastic,
      name: _me?.longName.isNotEmpty == true ? _me!.longName : link.name,
      hardware: hw == null ? null : MeshHardware.name(hw) ?? 'board $hw',
      firmware: _metadata?.firmware,
      address: myAddress,
      region: lora == null ? null : RegionCode.name(lora.region),
      preset: lora == null
          ? null
          : lora.usePreset
          ? ModemPreset.name(lora.modemPreset)
          : lora.modem?.toString(),
      modem: lora?.modem,
      notice: _notice,
      queueFree: _queueFree,
    );
  }

  @override
  Future<void> connect() async {
    _wanted = true;
    await _open();
  }

  Future<void> _open() async {
    _setStatus(const RadioLinkStatus(RadioLinkState.connecting));
    try {
      await link.open();
    } on RadioException catch (e) {
      _setStatus(
        RadioLinkStatus(
          RadioLinkState.failed,
          reason: e.message,
          permanent: e.permanent,
        ),
      );
      if (!e.permanent) _planReconnect();
      rethrow;
    }
    _queueFree = null;
    _reading = link.read.listen(
      _onBytes,
      onDone: _lost,
      onError: (Object _) => _lost(),
    );
    final configured = _configured = Completer<void>();
    try {
      await _askConfig();
      await configured.future.timeout(configTimeout);
    } on TimeoutException {
      await _closeLink();
      _setStatus(
        const RadioLinkStatus(
          RadioLinkState.failed,
          reason:
              'the device did not answer. Is it a Meshtastic device, and is '
              'it the right port?',
        ),
      );
      _planReconnect();
      throw const RadioException('the device did not send its configuration');
    } on RadioException {
      await _closeLink();
      _setStatus(
        const RadioLinkStatus(
          RadioLinkState.failed,
          reason: 'the link dropped while the device was answering',
        ),
      );
      _planReconnect();
      rethrow;
    }
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatEvery, (_) {
      _write(ToRadio.heartbeat()).catchError((Object _) {});
    });
    _setStatus(const RadioLinkStatus(RadioLinkState.connected));
  }

  /// Wakes the device (serial and TCP only) and asks for its settings.
  Future<void> _askConfig() async {
    if (!link.isBle) await link.write(ToRadio.wake);
    _configId = _random.nextInt(0x7FFFFFFF) + 1;
    await _write(ToRadio.wantConfig(_configId));
  }

  /// Asks for the settings again a little later: after a change that
  /// reboots the device, or when it says it has rebooted.
  void _planRefresh() {
    _refreshing?.cancel();
    _refreshing = Timer(rebootSettle, () {
      _refreshing = null;
      if (_reading == null || !_status.isUp) return;
      _queueFree = null;
      _askConfig().catchError((Object _) {});
    });
  }

  Future<void> _closeLink() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _refreshing?.cancel();
    _refreshing = null;
    await _reading?.cancel();
    _reading = null;
    await link.close();
    _wakeWaiters();
  }

  /// The link went away under us.
  void _lost() {
    if (!_wanted) return;
    _heartbeat?.cancel();
    _heartbeat = null;
    _refreshing?.cancel();
    _refreshing = null;
    _reading = null;
    _setStatus(const RadioLinkStatus(RadioLinkState.reconnecting));
    _wakeWaiters();
    _planReconnect();
  }

  void _planReconnect() {
    if (!_wanted || !reconnect || _reconnecting != null) return;
    _reconnecting = Timer(reconnectEvery, () async {
      _reconnecting = null;
      if (!_wanted) return;
      try {
        await _open();
      } on RadioException {
        // Status says why; another try is planned if it is worth one.
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _reconnecting?.cancel();
    _reconnecting = null;
    if (_reading != null) {
      try {
        await _write(ToRadio.disconnect());
      } on RadioException {
        // Gone already.
      }
    }
    await _closeLink();
    _setStatus(const RadioLinkStatus(RadioLinkState.disconnected));
  }

  Future<void> dispose() async {
    await disconnect();
    await _received.close();
    await _statuses.close();
    await _signals.close();
    await _deliveries.close();
  }

  Future<void> _write(Uint8List message) =>
      link.write(link.isBle ? message : StreamFramer.frame(message));

  void _onBytes(Uint8List bytes) {
    final messages = link.isBle ? [bytes] : _framer.feed(bytes);
    for (final message in messages) {
      final from = FromRadio.fromBytes(message);
      if (from == null) continue;
      _onFromRadio(from);
    }
  }

  void _onFromRadio(FromRadio from) {
    if (from.myInfo case final info?) _myNode = info.myNodeNum;
    if (from.metadata case final meta?) _metadata = meta;
    if (from.loraConfig case final lora?) _lora = lora;
    if (from.nodeInfo case final node?) {
      if (nodes.length < 512 || nodes.containsKey(node.num)) {
        nodes[node.num] = node;
      }
      if (node.num == _myNode) _me = node.user;
    }
    if (from.configCompleteId == _configId && _configId != 0) {
      _configured?.complete();
      _configured = null;
    }
    if (from.rebooted) {
      // Its settings may have changed, and it says nothing more until
      // asked: ask again.
      _queueFree = null;
      _planRefresh();
    }
    if (from.queueStatus case final queue?) _onQueue(queue);
    if (from.notice case final notice?) _onNotice(notice);
    if (from.packet case final packet?) _onPacket(packet);
  }

  void _onQueue(MeshQueueStatus queue) {
    if (queue.maxlen > 0 || queue.free > 0) _queueFree = queue.free;
    final id = queue.meshPacketId;
    if (queue.res != 0 && id != 0 && _ours.containsKey(id)) {
      _failed(id, 'the radio could not take it: its send queue is full');
    }
    _wakeWaiters();
  }

  void _onNotice(MeshNotice notice) {
    if (notice.message.isEmpty) return;
    _notice = notice.message;
    final id = notice.replyId;
    if (id != null && _ours.containsKey(id) && notice.level >= 30) {
      // The device held one of ours back and says why, in its own words
      // ("Duty cycle limit exceeded. You can send again in 12 mins"),
      // which say more than the routing error that follows.
      _failed(id, notice.message);
    }
  }

  void _wakeWaiters() {
    final waiting = List.of(_roomWaiters);
    _roomWaiters.clear();
    for (final waiter in waiting) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _onPacket(MeshPacket packet) {
    final data = packet.decoded;
    if (data == null) return;
    if (data.portnum == PortNum.routing) {
      _onRouting(packet, data);
      return;
    }
    if (data.portnum != PortNum.dnet) return;
    if (packet.id != 0) {
      if (!_heard.add(packet.id)) return;
      if (_heard.length > 512) _heard.remove(_heard.first);
    }
    final from = RadioAddress(packet.from);
    final rssi = packet.rxRssi == 0 ? null : packet.rxRssi;
    final snr = packet.rxSnr == 0 ? null : packet.rxSnr;
    _signals.add(RadioSignal(from: from, rssi: rssi, snr: snr));
    _received.add(
      RadioPacket(
        to: RadioAddress(packet.to),
        from: from,
        data: data.payload,
        id: packet.id,
        hopLimit: packet.hopLimit,
        wantAck: packet.wantAck,
        rssi: rssi,
        snr: snr,
        hopsTravelled: packet.hopsTravelled,
      ),
    );
  }

  /// A routing answer: `request_id` names the packet it is about. An
  /// error means failed, for any packet of ours (the device refuses a
  /// packet over the duty cycle whether an answer was asked for or not).
  /// No error, from the node the packet was for, means delivered; from
  /// any other node, that a device in between has it (an implicit
  /// acknowledgement).
  void _onRouting(MeshPacket packet, MeshData data) {
    final about = data.requestId;
    if (about == 0 || !_ours.containsKey(about)) return;
    final routing = MeshRouting.fromBytes(data.payload);
    if (routing == null) return;
    if (routing.errorReason != RoutingError.none) {
      _failed(about, RoutingError.describe(routing.errorReason));
      return;
    }
    if (!_awaiting.contains(about)) return;
    final destination = _ours[about];
    if (destination == null || packet.from == destination) {
      _forget(about);
      _deliveries.add(RadioDelivery(about, RadioDeliveryState.delivered));
    } else {
      _deliveries.add(RadioDelivery(about, RadioDeliveryState.relayed));
    }
  }

  void _failed(int id, String reason) {
    _forget(id);
    _deliveries.add(
      RadioDelivery(id, RadioDeliveryState.failed, reason: reason),
    );
  }

  void _forget(int id) {
    _ours.remove(id);
    _awaiting.remove(id);
  }

  void _remember(int id, int to, {required bool answer}) {
    _ours[id] = to;
    if (answer) _awaiting.add(id);
    while (_ours.length > 256) {
      final oldest = _ours.keys.first;
      _forget(oldest);
    }
  }

  /// Waits until the device's send queue has room, then claims a place.
  Future<void> _roomInQueue() async {
    final deadline = DateTime.now().add(queueWait);
    while ((_queueFree ?? 1) <= 0) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw const RadioException(
          'the radio\'s send queue stayed full: it is sending as fast as '
          'the band allows',
        );
      }
      final room = Completer<void>();
      _roomWaiters.add(room);
      try {
        await room.future.timeout(left);
      } on TimeoutException {
        _roomWaiters.remove(room);
      }
      if (!_status.isUp) {
        throw const RadioException('the radio is not connected');
      }
    }
    if (_queueFree case final free?) _queueFree = free - 1;
  }

  static int _priority(RadioPacket packet) => switch (packet.priority) {
    RadioPriority.background => MeshPriority.background,
    RadioPriority.high => MeshPriority.response,
    RadioPriority.normal =>
      packet.wantAck ? MeshPriority.reliable : MeshPriority.defaultPriority,
  };

  @override
  Future<void> send(RadioPacket packet) async {
    if (!_status.isUp) throw const RadioException('the radio is not connected');
    if (packet.data.length > mtu) {
      throw RadioException('a packet may be at most $mtu bytes');
    }
    await _roomInQueue();
    final id = packet.id == 0 ? _random.nextInt(0x7FFFFFFF) + 1 : packet.id;
    _remember(
      id,
      packet.to.node,
      answer: packet.wantAck && !packet.to.isEveryone,
    );
    final mesh = MeshPacket(
      to: packet.to.node,
      id: id,
      hopLimit: packet.hopLimit.clamp(0, 7),
      wantAck: packet.wantAck,
      priority: _priority(packet),
      decoded: MeshData(portnum: PortNum.dnet, payload: packet.data),
    );
    await _write(ToRadio.packet(mesh));
  }

  @override
  Future<void> setRegion(RadioRegion region) async {
    if (!_status.isUp) throw const RadioException('the radio is not connected');
    final code = region.meshtasticCode;
    final lora = _lora;
    if (code == null) {
      throw RadioException(
        '${region.name} has no Meshtastic region',
        permanent: true,
      );
    }
    if (lora == null) {
      throw const RadioException(
        'the device has not said its LoRa settings yet',
      );
    }
    // Already so: sending it again would only reboot the device.
    if (lora.region == code) return;
    final me = _myNode;
    if (me == null) {
      throw const RadioException('the device has not said who it is');
    }
    // An admin message to the device itself. The device reboots to apply
    // it and comes back with the new region.
    final admin = AdminMessage.setLoraConfig(lora.withRegion(code));
    await _write(
      ToRadio.packet(
        MeshPacket(
          to: me,
          id: _random.nextInt(0x7FFFFFFF) + 1,
          decoded: MeshData(
            portnum: PortNum.admin,
            payload: admin,
            wantResponse: true,
          ),
        ),
      ),
    );
    _lora = MeshLoraConfig.fromBytes(lora.withRegion(code));
    _planRefresh();
  }
}
