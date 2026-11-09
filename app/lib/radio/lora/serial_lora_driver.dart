import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'byte_link.dart';
import 'radio_transport.dart';

/// A bare LoRa module (an SX126x or SX127x on a small board) behind
/// DNet's own serial framing, for people who build their own node from a
/// module and a microcontroller instead of buying a Meshtastic board.
/// The firmware side is small: it takes these frames over the serial
/// port, puts the payload on the air, and hands back what it hears. The
/// wire format is in docs/RADIO.md, section "Generic serial modules".
///
/// Every frame, both ways:
///
/// ```text
/// 0xA5 0x5A | length (2 bytes, big-endian, of what follows) | type |
/// payload | CRC-16/CCITT (2 bytes, big-endian, over type and payload)
/// ```
///
/// Types the app sends: PING (0x01), CONFIG (0x02: region as frequency in
/// kHz (4), spreading factor (1), bandwidth in kHz (2), coding rate (1),
/// power in dBm (1)), SEND (0x03: to (4), hop limit (1), id (4), data),
/// STATUS (0x04: asks for the status).
///
/// Types the module sends: PONG (0x81: node number (4), firmware (string)),
/// RECV (0x83: from (4), to (4), id (4), hops (1), rssi (2, signed), snr
/// (1, signed, in quarter dB), data), STATUS (0x84: frequency kHz (4),
/// sf (1), bw kHz (2), cr (1), power (1), bps (4)), ERROR (0x8F: code (1),
/// text), SENT (0x85: id (4), ok (1)).
///
/// Not tried with real hardware. Checked against a stand-in module in
/// serial_lora_driver_test.dart.
class SerialLoraDriver implements RadioTransport {
  SerialLoraDriver(
    this.link, {
    this.pingTimeout = const Duration(seconds: 4),
    this.reconnectEvery = const Duration(seconds: 5),
    this.reconnect = true,
    Random? random,
  }) : _random = random ?? Random.secure();

  final ByteLink link;
  final Duration pingTimeout;
  final Duration reconnectEvery;
  final bool reconnect;
  final Random _random;

  final _received = StreamController<RadioPacket>.broadcast();
  final _statuses = StreamController<RadioLinkStatus>.broadcast();
  final _signals = StreamController<RadioSignal>.broadcast();
  final _deliveries = StreamController<RadioDelivery>.broadcast();
  final _framer = SerialFramer();

  RadioLinkStatus _status = const RadioLinkStatus(RadioLinkState.disconnected);
  StreamSubscription<Uint8List>? _reading;
  Timer? _reconnecting;
  Completer<SerialFrame>? _pong;
  bool _wanted = false;
  int? _myNode;
  String? _firmware;
  _ModuleStatus? _module;
  RadioRegion? _region;

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

  /// What a LoRa packet carries at most, less this framing's 13 bytes.
  @override
  int get mtu => 240;

  @override
  int? get bitsPerSecond => _module?.bitsPerSecond;

  /// The module's settings, where it has said them and they make sense.
  LoraModem? get _modem {
    final module = _module;
    if (module == null) return null;
    if (module.spreadingFactor < 5 || module.spreadingFactor > 12) return null;
    if (module.codingRate < 5 || module.codingRate > 8) return null;
    if (module.bandwidthKhz <= 0) return null;
    return LoraModem(
      spreadingFactor: module.spreadingFactor,
      bandwidthHz: module.bandwidthKhz * 1000,
      codingRate: module.codingRate,
      // RadioLib's default, which the reference firmware keeps.
      preambleSymbols: 8,
    );
  }

  /// The app's bytes plus the 13 the module puts on the air around them
  /// (to, from, id, hops): an estimate, since the module's own framing on
  /// the air is the firmware's choice.
  @override
  Duration? airtime(int bytes) => _modem?.airtime(bytes + 13);

  @override
  RadioDeviceInfo? get device => _myNode == null
      ? null
      : RadioDeviceInfo(
          kind: RadioDriverKind.serialLora,
          name: link.name,
          hardware: 'serial LoRa module',
          firmware: _firmware,
          address: myAddress,
          region: _region?.code,
          preset: _module == null
              ? null
              : 'SF${_module!.spreadingFactor} ${_module!.bandwidthKhz} kHz',
          modem: _modem,
        );

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
    _reading = link.read.listen(
      _onBytes,
      onDone: _lost,
      onError: (Object _) => _lost(),
    );
    final pong = _pong = Completer<SerialFrame>();
    await _send(SerialFrame(SerialFrameType.ping, Uint8List(0)));
    final SerialFrame answer;
    try {
      answer = await pong.future.timeout(pingTimeout);
    } on TimeoutException {
      await _closeLink();
      _setStatus(
        const RadioLinkStatus(
          RadioLinkState.failed,
          reason: 'nothing answered on the port: is the module flashed with DNet firmware?',
        ),
      );
      _planReconnect();
      throw const RadioException('the module did not answer');
    }
    final body = answer.payload;
    if (body.length >= 4) {
      _myNode = ByteData.sublistView(body).getUint32(0);
      _firmware = String.fromCharCodes(body.sublist(4));
    }
    await _send(SerialFrame(SerialFrameType.status, Uint8List(0)));
    _setStatus(const RadioLinkStatus(RadioLinkState.connected));
  }

  Future<void> _closeLink() async {
    await _reading?.cancel();
    _reading = null;
    await link.close();
  }

  void _lost() {
    if (!_wanted) return;
    _reading = null;
    _setStatus(const RadioLinkStatus(RadioLinkState.reconnecting));
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
        // The status says why.
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _reconnecting?.cancel();
    _reconnecting = null;
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

  Future<void> _send(SerialFrame frame) => link.write(frame.toBytes());

  void _onBytes(Uint8List bytes) {
    for (final frame in _framer.feed(bytes)) {
      _onFrame(frame);
    }
  }

  void _onFrame(SerialFrame frame) {
    final body = frame.payload;
    final data = ByteData.sublistView(body);
    switch (frame.type) {
      case SerialFrameType.pong:
        _pong?.complete(frame);
        _pong = null;
      case SerialFrameType.recv:
        if (body.length < 16) return;
        final from = data.getUint32(0);
        final to = data.getUint32(4);
        final id = data.getUint32(8);
        final hops = body[12];
        final rssi = data.getInt16(13);
        final snr = data.getInt8(15) / 4;
        final payload = body.sublist(16);
        final address = RadioAddress(from);
        _signals.add(RadioSignal(from: address, rssi: rssi, snr: snr));
        _received.add(
          RadioPacket(
            to: RadioAddress(to),
            from: address,
            data: payload,
            id: id,
            hopsTravelled: hops,
            rssi: rssi,
            snr: snr,
          ),
        );
      case SerialFrameType.moduleStatus:
        if (body.length < 13) return;
        _module = _ModuleStatus(
          frequencyKhz: data.getUint32(0),
          spreadingFactor: body[4],
          bandwidthKhz: data.getUint16(5),
          codingRate: body[7],
          powerDbm: data.getInt8(8),
          bitsPerSecond: data.getUint32(9),
        );
      case SerialFrameType.sent:
        if (body.length < 5) return;
        final id = data.getUint32(0);
        _deliveries.add(
          RadioDelivery(
            id,
            body[4] == 1 ? RadioDeliveryState.sent : RadioDeliveryState.failed,
            reason: body[4] == 1 ? null : 'the module could not send it',
          ),
        );
      case SerialFrameType.error:
        if (body.isNotEmpty && _pong != null) {
          _pong?.completeError(
            RadioException(String.fromCharCodes(body.sublist(1))),
          );
          _pong = null;
        }
      case SerialFrameType.ping ||
          SerialFrameType.config ||
          SerialFrameType.send ||
          SerialFrameType.status:
        // Ours to send, not to hear.
        break;
    }
  }

  @override
  Future<void> send(RadioPacket packet) async {
    if (!_status.isUp) throw const RadioException('the radio is not connected');
    if (packet.data.length > mtu) {
      throw RadioException('a packet may be at most $mtu bytes');
    }
    final id = packet.id == 0 ? _random.nextInt(0x7FFFFFFF) + 1 : packet.id;
    final body = Uint8List(9 + packet.data.length);
    ByteData.sublistView(body)
      ..setUint32(0, packet.to.node)
      ..setUint8(4, packet.hopLimit.clamp(0, 7))
      ..setUint32(5, id);
    body.setRange(9, body.length, packet.data);
    await _send(SerialFrame(SerialFrameType.send, body));
  }

  @override
  Future<void> setRegion(RadioRegion region) async {
    if (!_status.isUp) throw const RadioException('the radio is not connected');
    // The middle of the band, the usual long-range settings, and a power
    // within what the region allows. Where the rules cap the signal's
    // width below 250 kHz (India: 200 kHz), 125 kHz.
    final khz = ((region.mhzLow + region.mhzHigh) / 2 * 1000).round();
    final width = (region.maxBandwidthKhz ?? 250) < 250 ? 125 : 250;
    final body = Uint8List(9);
    ByteData.sublistView(body)
      ..setUint32(0, khz)
      ..setUint8(4, 11)
      ..setUint16(5, width)
      ..setUint8(7, 5)
      ..setInt8(8, min(region.maxPowerDbm ?? 14, 22));
    await _send(SerialFrame(SerialFrameType.config, body));
    _region = region;
    await _send(SerialFrame(SerialFrameType.status, Uint8List(0)));
  }
}

class _ModuleStatus {
  const _ModuleStatus({
    required this.frequencyKhz,
    required this.spreadingFactor,
    required this.bandwidthKhz,
    required this.codingRate,
    required this.powerDbm,
    required this.bitsPerSecond,
  });
  final int frequencyKhz;
  final int spreadingFactor;
  final int bandwidthKhz;
  final int codingRate;
  final int powerDbm;
  final int bitsPerSecond;
}

/// The frame types of the serial protocol.
enum SerialFrameType {
  ping(0x01),
  config(0x02),
  send(0x03),
  status(0x04),
  pong(0x81),
  recv(0x83),
  moduleStatus(0x84),
  sent(0x85),
  error(0x8F);

  const SerialFrameType(this.code);
  final int code;

  static SerialFrameType? of(int code) =>
      values.where((t) => t.code == code).firstOrNull;
}

/// One frame of the serial protocol.
class SerialFrame {
  const SerialFrame(this.type, this.payload);
  final SerialFrameType type;
  final Uint8List payload;

  static const magic1 = 0xA5;
  static const magic2 = 0x5A;

  /// The most a frame may carry. A LoRa packet is at most 255 bytes.
  static const mostPayload = 300;

  Uint8List toBytes() {
    final length = 1 + payload.length + 2;
    final out = Uint8List(4 + length);
    out[0] = magic1;
    out[1] = magic2;
    out[2] = length >> 8;
    out[3] = length & 0xFF;
    out[4] = type.code;
    out.setRange(5, 5 + payload.length, payload);
    final crc = crc16(out, 4, 5 + payload.length);
    out[out.length - 2] = crc >> 8;
    out[out.length - 1] = crc & 0xFF;
    return out;
  }

  /// CRC-16/CCITT-FALSE over [bytes] from [start] to [end].
  static int crc16(Uint8List bytes, int start, int end) {
    var crc = 0xFFFF;
    for (var i = start; i < end; i++) {
      crc ^= bytes[i] << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = crc & 0x8000 != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }
}

/// Reads frames out of a stream of bytes, skipping anything that is not
/// one: noise on the line, a boot message, a frame whose check fails.
class SerialFramer {
  final _pending = BytesBuilder(copy: false);

  List<SerialFrame> feed(List<int> data) {
    _pending.add(data);
    final frames = <SerialFrame>[];
    final bytes = _pending.takeBytes();
    var at = 0;
    while (true) {
      while (at + 1 < bytes.length &&
          !(bytes[at] == SerialFrame.magic1 &&
              bytes[at + 1] == SerialFrame.magic2)) {
        at++;
      }
      if (at + 4 > bytes.length) break;
      final length = (bytes[at + 2] << 8) | bytes[at + 3];
      if (length < 3 || length > SerialFrame.mostPayload + 3) {
        at++;
        continue;
      }
      if (at + 4 + length > bytes.length) break;
      final end = at + 4 + length;
      final said = (bytes[end - 2] << 8) | bytes[end - 1];
      if (said != SerialFrame.crc16(bytes, at + 4, end - 2)) {
        at++;
        continue;
      }
      final type = SerialFrameType.of(bytes[at + 4]);
      if (type != null) {
        frames.add(
          SerialFrame(type, Uint8List.fromList(bytes.sublist(at + 5, end - 2))),
        );
      }
      at = end;
    }
    if (at < bytes.length) {
      final rest = bytes.sublist(at);
      final most = SerialFrame.mostPayload + 8;
      _pending.add(
        rest.length > most ? rest.sublist(rest.length - most) : rest,
      );
    }
    return frames;
  }
}
