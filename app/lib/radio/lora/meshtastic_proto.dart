import 'dart:convert';
import 'dart:typed_data';

import 'radio_transport.dart' show LoraModem;

/// The parts of Meshtastic's protobuf API the app needs, read and written
/// by hand on the protobuf wire format. Field numbers are those of the
/// official `meshtastic/mesh.proto`, `config.proto` and `admin.proto`
/// (github.com/meshtastic/protobufs); only the fields the app uses are
/// named, and every other field is skipped as protobuf allows.
///
/// Nothing here is cryptography. It is a wire format: tags, varints and
/// lengths. Every reader is bounded and never throws on bad bytes: a
/// message that does not parse is simply null.
abstract final class Pb {
  static const varint = 0;
  static const fixed64 = 1;
  static const bytes = 2;
  static const fixed32 = 5;
}

/// Writes protobuf fields.
class PbWriter {
  final _out = BytesBuilder(copy: false);

  Uint8List toBytes() => _out.toBytes();

  void _tag(int field, int wire) => uvarint((field << 3) | wire);

  void uvarint(int value) {
    var v = value;
    while (v >= 0x80) {
      _out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _out.addByte(v);
  }

  void varintField(int field, int value) {
    if (value == 0) return;
    _tag(field, Pb.varint);
    uvarint(value);
  }

  /// An `int32` or `int64` field. A negative value goes on the wire as
  /// the ten-byte varint of its 64-bit two's complement, which is how
  /// protobuf writes `int32` (it is not zigzag: that is `sint32`).
  void int32Field(int field, int value) {
    if (value == 0) return;
    _tag(field, Pb.varint);
    var v = value;
    while (v < 0 || v >= 0x80) {
      _out.addByte((v & 0x7F) | 0x80);
      v = v >>> 7;
    }
    _out.addByte(v);
  }

  void boolField(int field, bool value) {
    if (value) varintField(field, 1);
  }

  void fixed32Field(int field, int value) {
    if (value == 0) return;
    _tag(field, Pb.fixed32);
    final b = ByteData(4)..setUint32(0, value & 0xFFFFFFFF, Endian.little);
    _out.add(b.buffer.asUint8List());
  }

  void floatField(int field, double value) {
    if (value == 0) return;
    _tag(field, Pb.fixed32);
    final b = ByteData(4)..setFloat32(0, value, Endian.little);
    _out.add(b.buffer.asUint8List());
  }

  void bytesField(int field, List<int> value) {
    if (value.isEmpty) return;
    _tag(field, Pb.bytes);
    uvarint(value.length);
    _out.add(value);
  }

  void stringField(int field, String value) =>
      bytesField(field, utf8.encode(value));

  void messageField(int field, PbWriter inner) =>
      bytesField(field, inner.toBytes());

  /// Writes a sub-message even when empty: protobuf tells "set but
  /// empty" from "unset" by the field being present.
  void presentMessageField(int field, PbWriter inner) {
    _tag(field, Pb.bytes);
    final bytes = inner.toBytes();
    uvarint(bytes.length);
    _out.add(bytes);
  }
}

/// One field as read.
class PbField {
  const PbField(this.number, this.wire, this.value, this.bytes);
  final int number;
  final int wire;

  /// For varint and fixed fields.
  final int value;

  /// For length-delimited fields.
  final Uint8List? bytes;

  double get asFloat => wire == Pb.fixed32
      ? (ByteData(
          4,
        )..setUint32(0, value, Endian.little)).getFloat32(0, Endian.little)
      : 0;

  /// A signed varint (sint32 in the schema): zigzag.
  int get asSint => (value >> 1) ^ -(value & 1);

  /// An `int32` in the schema: a negative one arrives as a ten-byte
  /// varint, read here as a 64-bit number, so the low 32 bits are kept
  /// and read as signed.
  int get asInt32 => value.toSigned(32);

  String get asString {
    try {
      return utf8.decode(bytes ?? const [], allowMalformed: false);
    } on FormatException {
      return '';
    }
  }
}

/// Reads protobuf fields one by one. Stops, and says so, at the first
/// byte that does not parse.
class PbReader {
  PbReader(this._bytes);
  final Uint8List _bytes;
  int _at = 0;
  bool malformed = false;

  /// The most bytes a message may be: Meshtastic's are small, and a
  /// length far beyond is an attack or garbage.
  static const mostLength = 1 << 16;

  int? _uvarint() {
    var shift = 0;
    var value = 0;
    while (_at < _bytes.length) {
      final b = _bytes[_at++];
      value |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) return value;
      shift += 7;
      if (shift > 63) break;
    }
    return null;
  }

  /// The next field, or null at the end or at the first bad byte.
  PbField? next() {
    if (malformed || _at >= _bytes.length) return null;
    final key = _uvarint();
    if (key == null) return _bad();
    final number = key >> 3;
    final wire = key & 7;
    if (number == 0) return _bad();
    switch (wire) {
      case Pb.varint:
        final value = _uvarint();
        if (value == null) return _bad();
        return PbField(number, wire, value, null);
      case Pb.fixed32:
        if (_at + 4 > _bytes.length) return _bad();
        final value = ByteData.sublistView(
          _bytes,
          _at,
          _at + 4,
        ).getUint32(0, Endian.little);
        _at += 4;
        return PbField(number, wire, value, null);
      case Pb.fixed64:
        if (_at + 8 > _bytes.length) return _bad();
        _at += 8;
        return PbField(number, wire, 0, null);
      case Pb.bytes:
        final length = _uvarint();
        if (length == null ||
            length > mostLength ||
            _at + length > _bytes.length) {
          return _bad();
        }
        final bytes = Uint8List.sublistView(_bytes, _at, _at + length);
        _at += length;
        return PbField(number, wire, 0, bytes);
      default:
        return _bad();
    }
  }

  PbField? _bad() {
    malformed = true;
    return null;
  }

  /// Every field, or null if the bytes do not parse to the end.
  static List<PbField>? all(Uint8List bytes) {
    final reader = PbReader(bytes);
    final fields = <PbField>[];
    for (var f = reader.next(); f != null; f = reader.next()) {
      fields.add(f);
      if (fields.length > 4096) return null;
    }
    return reader.malformed ? null : fields;
  }
}

/// Meshtastic port numbers the app uses.
abstract final class PortNum {
  static const textMessage = 1;
  static const routing = 5;
  static const admin = 6;

  /// Where the app's own packets go. Meshtastic keeps 256–511 for
  /// private apps like this one.
  static const dnet = 256;
}

/// `MeshPacket.priority`. The device sends the highest first.
abstract final class MeshPriority {
  static const unset = 0;
  static const background = 10;
  static const defaultPriority = 64;
  static const reliable = 70;
  static const response = 80;
  static const high = 100;
  static const ack = 120;
}

/// Sizes the firmware works to (`RadioInterface.h`, `mesh.proto`).
abstract final class MeshLimits {
  /// The most a LoRa packet carries (SX12xx datasheets).
  static const loraPayload = 255;

  /// The firmware's own header on every packet: to, from, id, flags,
  /// channel, next hop, relay node.
  static const header = 16;

  /// What public-key encryption adds to a direct message (2.5 and later):
  /// an authentication tag and a nonce part.
  static const pkcOverhead = 12;

  /// Around the app's bytes inside `Data`: the port number (3 bytes for
  /// 256), the payload's tag and length (3), and the `bitfield` the
  /// firmware adds to everything it sends (2).
  static const dataOverhead = 8;

  /// The most app bytes that fit one packet in every case today:
  /// 255 - 16 - 12 - 8 = 219.
  static const appPayload = loraPayload - header - pkcOverhead - dataOverhead;

  /// `Constants.DATA_PAYLOAD_LEN`: the firmware's limit for a payload on
  /// a channel without public-key encryption.
  static const dataPayloadLen = 233;

  /// The most bytes of one framed `ToRadio`/`FromRadio`.
  static const streamFrame = 512;
}

/// `Routing.Error`, which comes back for a packet sent with `want_ack`.
abstract final class RoutingError {
  static const none = 0;
  static const noRoute = 1;
  static const gotNak = 2;
  static const timeout = 3;
  static const noInterface = 4;
  static const maxRetransmit = 5;
  static const noChannel = 6;
  static const tooLarge = 7;
  static const noResponse = 8;
  static const dutyCycleLimit = 9;
  static const badRequest = 32;
  static const notAuthorized = 33;
  static const pkiFailed = 34;
  static const pkiUnknownPubkey = 35;
  static const adminBadSessionKey = 36;
  static const adminPublicKeyUnauthorized = 37;
  static const rateLimitExceeded = 38;
  static const pkiSendFailPublicKey = 39;

  /// What went wrong, in plain words for the screen.
  static String describe(int code) => switch (code) {
    none => 'delivered',
    noRoute => 'no radio on the way knows a route to that device',
    gotNak => 'the other radio refused it',
    timeout => 'timed out waiting for an answer',
    noInterface => 'the radio has no LoRa chip working',
    maxRetransmit =>
      'no answer after every retry: out of range, or switched off',
    noChannel => 'the radio has no channel for it',
    tooLarge => 'the packet is too large for the radio',
    noResponse => 'no response',
    dutyCycleLimit =>
      'the radio has used all the airtime the law allows this hour; '
          'it sends again later',
    badRequest => 'the radio did not understand the request',
    notAuthorized => 'the radio refused: not authorised',
    pkiFailed || pkiUnknownPubkey || pkiSendFailPublicKey =>
      'the radios could not agree a key for a direct packet; '
          'they need to hear each other\'s node info first',
    adminBadSessionKey ||
    adminPublicKeyUnauthorized => 'the radio refused the settings change',
    rateLimitExceeded => 'the radio is sending too fast and held this back',
    _ => 'the radio reported error $code',
  };
}

/// `Config.LoRaConfig.RegionCode`.
abstract final class RegionCode {
  static const unset = 0;
  static const us = 1;
  static const eu433 = 2;
  static const eu868 = 3;
  static const cn = 4;
  static const jp = 5;
  static const anz = 6;
  static const kr = 7;
  static const tw = 8;
  static const ru = 9;
  static const india = 10;
  static const nz865 = 11;
  static const th = 12;
  static const lora24 = 13;
  static const ua433 = 14;
  static const ua868 = 15;
  static const my433 = 16;
  static const my919 = 17;
  static const sg923 = 18;
  static const ph433 = 19;
  static const ph868 = 20;
  static const ph915 = 21;
  static const anz433 = 22;
  static const kz433 = 23;
  static const kz863 = 24;
  static const np865 = 25;
  static const br902 = 26;

  static String name(int code) => switch (code) {
    unset => 'UNSET',
    us => 'US',
    eu433 => 'EU_433',
    eu868 => 'EU_868',
    cn => 'CN',
    jp => 'JP',
    anz => 'ANZ',
    kr => 'KR',
    tw => 'TW',
    ru => 'RU',
    india => 'IN',
    nz865 => 'NZ_865',
    th => 'TH',
    lora24 => 'LORA_24',
    ua433 => 'UA_433',
    ua868 => 'UA_868',
    my433 => 'MY_433',
    my919 => 'MY_919',
    sg923 => 'SG_923',
    ph433 => 'PH_433',
    ph868 => 'PH_868',
    ph915 => 'PH_915',
    anz433 => 'ANZ_433',
    kz433 => 'KZ_433',
    kz863 => 'KZ_863',
    np865 => 'NP_865',
    br902 => 'BR_902',
    _ => 'REGION_$code',
  };
}

/// `Config.LoRaConfig.ModemPreset`, and what each one sends with.
abstract final class ModemPreset {
  static const longFast = 0;
  static const longSlow = 1;
  static const veryLongSlow = 2;
  static const mediumSlow = 3;
  static const mediumFast = 4;
  static const shortSlow = 5;
  static const shortFast = 6;
  static const longModerate = 7;
  static const shortTurbo = 8;
  static const longTurbo = 9;

  static String name(int preset) => switch (preset) {
    longFast => 'LONG_FAST',
    longSlow => 'LONG_SLOW',
    veryLongSlow => 'VERY_LONG_SLOW',
    mediumSlow => 'MEDIUM_SLOW',
    mediumFast => 'MEDIUM_FAST',
    shortSlow => 'SHORT_SLOW',
    shortFast => 'SHORT_FAST',
    longModerate => 'LONG_MODERATE',
    shortTurbo => 'SHORT_TURBO',
    longTurbo => 'LONG_TURBO',
    10 => 'LITE_FAST',
    11 => 'LITE_SLOW',
    12 => 'NARROW_FAST',
    13 => 'NARROW_SLOW',
    14 => 'TINY_FAST',
    15 => 'TINY_SLOW',
    16 => 'MEDIUM_TURBO',
    _ => 'PRESET_$preset',
  };

  /// The bandwidth, spreading factor and coding rate of each preset, as
  /// the firmware sets them (`modemPresetToParams` in MeshRadio.h), with
  /// Meshtastic's 16-symbol preamble. Null for a preset newer than this
  /// table: the screen then says the airtime is unknown rather than guess.
  static LoraModem? modem(int preset) => switch (preset) {
    shortTurbo => _m(7, 500, 5),
    shortFast => _m(7, 250, 5),
    shortSlow => _m(8, 250, 5),
    mediumFast => _m(9, 250, 5),
    mediumSlow => _m(10, 250, 5),
    longFast => _m(11, 250, 5),
    longTurbo => _m(11, 500, 8),
    longModerate => _m(11, 125, 8),
    longSlow => _m(12, 125, 8),
    veryLongSlow => _m(12, 62.5, 8),
    _ => null,
  };

  static LoraModem _m(int sf, num khz, int cr) => LoraModem(
    spreadingFactor: sf,
    bandwidthHz: (khz * 1000).round(),
    codingRate: cr,
  );

  /// Bits a second on the air. LONG_FAST's 1 kbit/s for a preset not in
  /// the table.
  static int bitsPerSecond(int preset) => modem(preset)?.bitsPerSecond ?? 1074;
}

/// `HardwareModel`: names for the boards people most often pair with the
/// app, so the screen says "Heltec V3" rather than a number.
abstract final class MeshHardware {
  static String? name(int model) => switch (model) {
    4 => 'LILYGO T-Beam',
    7 => 'LILYGO T-Echo',
    9 => 'RAK WisBlock 4631',
    12 => 'LILYGO T-Beam S3 Core',
    16 => 'LILYGO T3-S3',
    18 => 'Nano G2 Ultra',
    31 => 'Station G2',
    43 => 'Heltec V3',
    44 => 'Heltec Wireless Stick Lite V3',
    48 => 'Heltec Wireless Tracker',
    71 => 'SenseCAP T1000-E',
    81 => 'Seeed XIAO ESP32-S3',
    84 => 'WisMesh Tap',
    110 => 'Heltec V4',
    _ => null,
  };
}

/// `MeshPacket`, the fields the app reads and writes.
class MeshPacket {
  const MeshPacket({
    this.from = 0,
    this.to = 0,
    this.channel = 0,
    this.id = 0,
    this.rxTime = 0,
    this.rxSnr = 0,
    this.hopLimit = 0,
    this.wantAck = false,
    this.priority = 0,
    this.rxRssi = 0,
    this.hopStart = 0,
    this.viaMqtt = false,
    this.decoded,
    this.encrypted,
  });

  final int from;
  final int to;
  final int channel;
  final int id;
  final int rxTime;
  final double rxSnr;
  final int hopLimit;
  final bool wantAck;
  final int priority;
  final int rxRssi;
  final int hopStart;

  /// Whether it crossed an internet (MQTT) bridge on the way. DNet never
  /// asks for that (it leaves the device's "OK to MQTT" off), but another
  /// node on the mesh may run one.
  final bool viaMqtt;
  final MeshData? decoded;
  final Uint8List? encrypted;

  /// How many devices passed it on, where the packet says where it
  /// started. Null otherwise.
  int? get hopsTravelled =>
      hopStart > 0 && hopStart >= hopLimit ? hopStart - hopLimit : null;

  Uint8List toBytes() {
    final w = PbWriter()
      ..fixed32Field(1, from)
      ..fixed32Field(2, to)
      ..varintField(3, channel);
    if (decoded case final data?) w.messageField(4, data.toWriter());
    if (encrypted case final bytes?) w.bytesField(5, bytes);
    w
      ..fixed32Field(6, id)
      ..fixed32Field(7, rxTime)
      ..floatField(8, rxSnr)
      ..varintField(9, hopLimit)
      ..boolField(10, wantAck)
      ..varintField(11, priority);
    w
      ..int32Field(12, rxRssi)
      ..boolField(14, viaMqtt)
      ..varintField(15, hopStart);
    return w.toBytes();
  }

  static MeshPacket? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var packet = const MeshPacket();
    var from = 0, to = 0, channel = 0, id = 0, rxTime = 0, hopLimit = 0;
    var priority = 0, rxRssi = 0, hopStart = 0;
    var rxSnr = 0.0;
    var wantAck = false, viaMqtt = false;
    MeshData? decoded;
    Uint8List? encrypted;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          from = f.value;
        case 2:
          to = f.value;
        case 3:
          channel = f.value;
        case 4:
          if (f.bytes != null) decoded = MeshData.fromBytes(f.bytes!);
        case 5:
          encrypted = f.bytes;
        case 6:
          id = f.value;
        case 7:
          rxTime = f.value;
        case 8:
          rxSnr = f.asFloat;
        case 9:
          hopLimit = f.value;
        case 10:
          wantAck = f.value != 0;
        case 11:
          priority = f.value;
        case 12:
          // `int32`, not zigzag: -97 dBm arrives as ten bytes.
          rxRssi = f.asInt32;
        case 14:
          viaMqtt = f.value != 0;
        case 15:
          hopStart = f.value;
      }
    }
    packet = MeshPacket(
      from: from,
      to: to,
      channel: channel,
      id: id,
      rxTime: rxTime,
      rxSnr: rxSnr,
      hopLimit: hopLimit,
      wantAck: wantAck,
      priority: priority,
      rxRssi: rxRssi,
      hopStart: hopStart,
      viaMqtt: viaMqtt,
      decoded: decoded,
      encrypted: encrypted,
    );
    return packet;
  }
}

/// `Data`: what a decoded packet carries.
class MeshData {
  const MeshData({
    required this.portnum,
    required this.payload,
    this.wantResponse = false,
    this.dest = 0,
    this.source = 0,
    this.requestId = 0,
    this.replyId = 0,
  });

  final int portnum;
  final Uint8List payload;
  final bool wantResponse;
  final int dest;
  final int source;
  final int requestId;
  final int replyId;

  PbWriter toWriter() => PbWriter()
    ..varintField(1, portnum)
    ..bytesField(2, payload)
    ..boolField(3, wantResponse)
    ..fixed32Field(4, dest)
    ..fixed32Field(5, source)
    ..fixed32Field(6, requestId)
    ..fixed32Field(7, replyId);

  static MeshData? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var portnum = 0, dest = 0, source = 0, requestId = 0, replyId = 0;
    var wantResponse = false;
    var payload = Uint8List(0);
    for (final f in fields) {
      switch (f.number) {
        case 1:
          portnum = f.value;
        case 2:
          payload = f.bytes ?? payload;
        case 3:
          wantResponse = f.value != 0;
        case 4:
          dest = f.value;
        case 5:
          source = f.value;
        case 6:
          requestId = f.value;
        case 7:
          replyId = f.value;
      }
    }
    return MeshData(
      portnum: portnum,
      payload: payload,
      wantResponse: wantResponse,
      dest: dest,
      source: source,
      requestId: requestId,
      replyId: replyId,
    );
  }
}

/// `Routing`, carried on [PortNum.routing]: the answer to `want_ack`.
class MeshRouting {
  const MeshRouting({this.errorReason = 0});
  final int errorReason;

  static MeshRouting? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var error = 0;
    for (final f in fields) {
      if (f.number == 3) error = f.value;
    }
    return MeshRouting(errorReason: error);
  }
}

/// `User`, inside a `NodeInfo`.
class MeshUser {
  const MeshUser({
    this.id = '',
    this.longName = '',
    this.shortName = '',
    this.hwModel = 0,
  });
  final String id;
  final String longName;
  final String shortName;
  final int hwModel;

  static MeshUser? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var id = '', long = '', short = '';
    var hw = 0;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          id = f.asString;
        case 2:
          long = f.asString;
        case 3:
          short = f.asString;
        case 5:
          hw = f.value;
      }
    }
    return MeshUser(id: id, longName: long, shortName: short, hwModel: hw);
  }
}

/// `NodeInfo`: a node the device knows of.
class MeshNodeInfo {
  const MeshNodeInfo({
    required this.num,
    this.user,
    this.snr = 0,
    this.lastHeard = 0,
    this.hopsAway = 0,
  });
  final int num;
  final MeshUser? user;
  final double snr;
  final int lastHeard;
  final int hopsAway;

  static MeshNodeInfo? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var num = 0, lastHeard = 0, hops = 0;
    var snr = 0.0;
    MeshUser? user;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          num = f.value;
        case 2:
          if (f.bytes != null) user = MeshUser.fromBytes(f.bytes!);
        case 4:
          snr = f.asFloat;
        case 5:
          lastHeard = f.value;
        case 9:
          hops = f.value;
      }
    }
    return MeshNodeInfo(
      num: num,
      user: user,
      snr: snr,
      lastHeard: lastHeard,
      hopsAway: hops,
    );
  }
}

/// `MyNodeInfo`: the device's own number.
class MeshMyInfo {
  const MeshMyInfo({required this.myNodeNum});
  final int myNodeNum;

  static MeshMyInfo? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var num = 0;
    for (final f in fields) {
      if (f.number == 1) num = f.value;
    }
    return MeshMyInfo(myNodeNum: num);
  }
}

/// `DeviceMetadata`: the firmware and board.
class MeshMetadata {
  const MeshMetadata({this.firmware = '', this.hwModel = 0});
  final String firmware;
  final int hwModel;

  static MeshMetadata? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var firmware = '';
    var hw = 0;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          firmware = f.asString;
        case 9:
          hw = f.value;
      }
    }
    return MeshMetadata(firmware: firmware, hwModel: hw);
  }
}

/// `Config.LoRaConfig`, the fields that matter here. Kept whole as the
/// raw bytes too, so a change of region can be sent back with every
/// other setting as it was.
class MeshLoraConfig {
  const MeshLoraConfig({
    required this.raw,
    this.usePreset = true,
    this.modemPreset = 0,
    this.region = 0,
    this.hopLimit = 3,
    this.txEnabled = true,
    this.txPower = 0,
    this.overrideDutyCycle = false,
    this.bandwidth = 0,
    this.spreadFactor = 0,
    this.codingRate = 0,
  });

  final Uint8List raw;
  final bool usePreset;
  final int modemPreset;
  final int region;
  final int hopLimit;
  final bool txEnabled;
  final int txPower;
  final bool overrideDutyCycle;

  /// The radio's own settings, used when [usePreset] is off. Bandwidth is
  /// in kHz, with a few numbers standing for the fractional widths.
  final int bandwidth;
  final int spreadFactor;
  final int codingRate;

  /// What the radio sends with: the preset's settings, or its own.
  LoraModem? get modem {
    if (usePreset) return ModemPreset.modem(modemPreset);
    if (spreadFactor < 5 || spreadFactor > 12) return null;
    if (codingRate < 5 || codingRate > 8) return null;
    final khz = switch (bandwidth) {
      7 => 7.8,
      10 => 10.4,
      15 => 15.6,
      20 => 20.8,
      31 => 31.25,
      41 => 41.7,
      62 => 62.5,
      final other => other.toDouble(),
    };
    if (khz <= 0) return null;
    return LoraModem(
      spreadingFactor: spreadFactor,
      bandwidthHz: (khz * 1000).round(),
      codingRate: codingRate,
    );
  }

  static MeshLoraConfig? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var usePreset = false, tx = false, overrideDuty = false;
    var preset = 0, region = 0, hop = 0, power = 0;
    var bandwidth = 0, spread = 0, coding = 0;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          usePreset = f.value != 0;
        case 2:
          preset = f.value;
        case 3:
          bandwidth = f.value;
        case 4:
          spread = f.value;
        case 5:
          coding = f.value;
        case 7:
          region = f.value;
        case 8:
          hop = f.value;
        case 9:
          tx = f.value != 0;
        case 10:
          power = f.asInt32;
        case 12:
          overrideDuty = f.value != 0;
      }
    }
    return MeshLoraConfig(
      raw: bytes,
      usePreset: usePreset,
      modemPreset: preset,
      region: region,
      hopLimit: hop,
      txEnabled: tx,
      txPower: power,
      overrideDutyCycle: overrideDuty,
      bandwidth: bandwidth,
      spreadFactor: spread,
      codingRate: coding,
    );
  }

  /// The same config with [region] put in, every other field copied as
  /// it came. The region is field 7.
  Uint8List withRegion(int newRegion) {
    final fields = PbReader.all(raw) ?? const [];
    final w = PbWriter();
    for (final f in fields) {
      if (f.number == 7) continue;
      switch (f.wire) {
        case Pb.varint:
          w._tag(f.number, Pb.varint);
          w.uvarint(f.value);
        case Pb.fixed32:
          w._tag(f.number, Pb.fixed32);
          final b = ByteData(4)..setUint32(0, f.value, Endian.little);
          w._out.add(b.buffer.asUint8List());
        case Pb.bytes:
          w.bytesField(f.number, f.bytes ?? const []);
        default:
          break;
      }
    }
    w.varintField(7, newRegion);
    return w.toBytes();
  }
}

/// What the device sends the app: one `FromRadio`.
class FromRadio {
  const FromRadio({
    this.id = 0,
    this.packet,
    this.myInfo,
    this.nodeInfo,
    this.loraConfig,
    this.configCompleteId,
    this.rebooted = false,
    this.metadata,
    this.channelBytes,
    this.queueStatus,
    this.notice,
  });

  /// How full the device's send queue is, after a packet was handed to it.
  final MeshQueueStatus? queueStatus;

  /// Something the device wants the user told, such as "Duty cycle limit
  /// exceeded".
  final MeshNotice? notice;

  final int id;
  final MeshPacket? packet;
  final MeshMyInfo? myInfo;
  final MeshNodeInfo? nodeInfo;

  /// Set when the `config` field carried a LoRa config.
  final MeshLoraConfig? loraConfig;
  final int? configCompleteId;
  final bool rebooted;
  final MeshMetadata? metadata;
  final Uint8List? channelBytes;

  static FromRadio? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var id = 0;
    var rebooted = false;
    int? complete;
    MeshPacket? packet;
    MeshMyInfo? myInfo;
    MeshNodeInfo? nodeInfo;
    MeshLoraConfig? lora;
    MeshMetadata? metadata;
    Uint8List? channel;
    MeshQueueStatus? queue;
    MeshNotice? notice;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          id = f.value;
        case 2:
          if (f.bytes != null) packet = MeshPacket.fromBytes(f.bytes!);
        case 3:
          if (f.bytes != null) myInfo = MeshMyInfo.fromBytes(f.bytes!);
        case 4:
          if (f.bytes != null) nodeInfo = MeshNodeInfo.fromBytes(f.bytes!);
        case 5:
          // Config: which of its sub-messages is set says which config.
          for (final c in PbReader.all(f.bytes ?? Uint8List(0)) ?? const []) {
            if (c.number == 6 && c.bytes != null) {
              lora = MeshLoraConfig.fromBytes(c.bytes!);
            }
          }
        case 7:
          complete = f.value;
        case 8:
          rebooted = f.value != 0;
        case 10:
          channel = f.bytes;
        case 11:
          if (f.bytes != null) queue = MeshQueueStatus.fromBytes(f.bytes!);
        case 13:
          if (f.bytes != null) metadata = MeshMetadata.fromBytes(f.bytes!);
        case 16:
          if (f.bytes != null) notice = MeshNotice.fromBytes(f.bytes!);
      }
    }
    return FromRadio(
      id: id,
      packet: packet,
      myInfo: myInfo,
      nodeInfo: nodeInfo,
      loraConfig: lora,
      configCompleteId: complete,
      rebooted: rebooted,
      metadata: metadata,
      channelBytes: channel,
      queueStatus: queue,
      notice: notice,
    );
  }
}

/// `QueueStatus`: the device's answer to each packet handed to it. [res]
/// is zero when the packet was queued; [free] and [maxlen] say how much
/// room is left in its send queue. The official clients wait for room
/// before handing over the next packet; so does the app.
class MeshQueueStatus {
  const MeshQueueStatus({
    this.res = 0,
    this.free = 0,
    this.maxlen = 0,
    this.meshPacketId = 0,
  });
  final int res;
  final int free;
  final int maxlen;
  final int meshPacketId;

  static MeshQueueStatus? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    var res = 0, free = 0, maxlen = 0, id = 0;
    for (final f in fields) {
      switch (f.number) {
        case 1:
          res = f.asInt32;
        case 2:
          free = f.value;
        case 3:
          maxlen = f.value;
        case 4:
          id = f.value;
      }
    }
    return MeshQueueStatus(
      res: res,
      free: free,
      maxlen: maxlen,
      meshPacketId: id,
    );
  }

  Uint8List toBytes() =>
      (PbWriter()
            ..int32Field(1, res)
            ..varintField(2, free)
            ..varintField(3, maxlen)
            ..varintField(4, meshPacketId))
          .toBytes();
}

/// `ClientNotification`: a message from the device for the user, about
/// one packet ([replyId]) or none. The firmware sends one when it holds a
/// packet back for the duty cycle: "Duty cycle limit exceeded. You can
/// send again in 12 mins".
class MeshNotice {
  const MeshNotice({this.replyId, this.level = 0, this.message = ''});
  final int? replyId;

  /// `LogRecord.Level`: 30 a warning, 40 an error, 50 critical.
  final int level;
  final String message;

  static MeshNotice? fromBytes(Uint8List bytes) {
    final fields = PbReader.all(bytes);
    if (fields == null) return null;
    int? reply;
    var level = 0;
    var message = '';
    for (final f in fields) {
      switch (f.number) {
        case 1:
          reply = f.value;
        case 3:
          level = f.value;
        case 4:
          message = f.asString;
      }
    }
    // A device's words go on screen: kept short and on one line.
    message = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (message.length > 160) message = '${message.substring(0, 160)}…';
    return MeshNotice(replyId: reply, level: level, message: message);
  }

  Uint8List toBytes() {
    final w = PbWriter();
    if (replyId case final id?) {
      w._tag(1, Pb.varint);
      w.uvarint(id);
    }
    return (w
          ..varintField(3, level)
          ..stringField(4, message))
        .toBytes();
  }
}

/// What the app sends the device: one `ToRadio`.
abstract final class ToRadio {
  static Uint8List packet(MeshPacket packet) =>
      (PbWriter()..messageField(1, PbWriter()..uvarintRaw(packet.toBytes())))
          .toBytes();

  static Uint8List wantConfig(int id) =>
      (PbWriter()..varintField(3, id)).toBytes();

  static Uint8List disconnect() => (PbWriter()..boolField(4, true)).toBytes();

  static Uint8List heartbeat() =>
      (PbWriter()..presentMessageField(7, PbWriter())).toBytes();

  /// Sent before anything else on a serial or TCP link, as the official
  /// clients do: wakes a device that is asleep, and makes one whose
  /// reader was halfway through a broken frame start looking for a new
  /// one (`stream_interface.py`, `connect`).
  static final wake = Uint8List.fromList(List.filled(32, StreamFramer.magic2));
}

extension on PbWriter {
  /// Adds already-encoded bytes as the body of this writer.
  void uvarintRaw(Uint8List bytes) => _out.add(bytes);
}

/// `AdminMessage`, sent to the device itself to change a setting.
abstract final class AdminMessage {
  /// `set_config { lora: <bytes> }`: field 34 is `set_config`, and inside
  /// `Config`, field 6 is `lora`. From the app over its own link the
  /// device needs no session key (that is for admin from other nodes);
  /// it saves the change and reboots to apply it.
  static Uint8List setLoraConfig(Uint8List loraConfig) {
    final config = PbWriter()..bytesField(6, loraConfig);
    return (PbWriter()..messageField(34, config)).toBytes();
  }
}

/// The stream framing used over USB serial and TCP: two magic bytes,
/// a big-endian length, then one `FromRadio` or `ToRadio`. Bytes that
/// are not a frame (the device's debug log, for instance) are skipped.
class StreamFramer {
  static const magic1 = 0x94;
  static const magic2 = 0xC3;

  /// The most a frame may be. Meshtastic's own limit is 512.
  static const mostFrame = MeshLimits.streamFrame;

  final _pending = BytesBuilder(copy: false);

  /// Frames a message for sending.
  static Uint8List frame(Uint8List message) {
    final out = Uint8List(4 + message.length);
    out[0] = magic1;
    out[1] = magic2;
    out[2] = message.length >> 8;
    out[3] = message.length & 0xFF;
    out.setRange(4, out.length, message);
    return out;
  }

  /// Takes bytes as they arrive and gives back every whole frame in
  /// them. A false start (magic with an impossible length) is skipped a
  /// byte at a time, so the stream recovers.
  List<Uint8List> feed(List<int> data) {
    _pending.add(data);
    final frames = <Uint8List>[];
    var bytes = _pending.takeBytes();
    var at = 0;
    while (true) {
      // Find the magic.
      while (at + 1 < bytes.length &&
          !(bytes[at] == magic1 && bytes[at + 1] == magic2)) {
        at++;
      }
      if (at + 4 > bytes.length) break;
      final length = (bytes[at + 2] << 8) | bytes[at + 3];
      if (length > mostFrame) {
        at += 1;
        continue;
      }
      if (at + 4 + length > bytes.length) break;
      frames.add(Uint8List.fromList(bytes.sublist(at + 4, at + 4 + length)));
      at += 4 + length;
    }
    if (at < bytes.length) {
      // Keep what is left, but never more than one frame's worth of
      // nothing: a stream of garbage must not grow it for ever.
      final rest = bytes.sublist(at);
      _pending.add(
        rest.length > mostFrame + 4
            ? rest.sublist(rest.length - mostFrame - 4)
            : rest,
      );
    }
    return frames;
  }
}
