import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'radio_transport.dart';

/// What the app says over a LoRa radio, on top of whatever the radio
/// itself does.
///
/// A LoRa packet is tiny (about 200 bytes), slow (a second or more on the
/// air) and often lost. The core's link protocol wants to move messages
/// of a kilobyte or more and be sure they arrived. This layer sits in
/// between and gives it:
///
/// - **Fragments.** A message is cut into fragments that fit one packet
///   and put back together at the other end, in any order.
/// - **Acknowledgement and retries.** A message is answered with an ACK
///   naming the fragments still missing; only those are sent again, with
///   the wait doubling each time. After [RadioProtocolConfig.tries] the
///   message has failed, and the app is told.
/// - **Waits that fit the radio.** How long to wait for an ACK is worked
///   out from how long the fragments and the ACK take on the air, times
///   the hops they may cross, until the first round trips to a device
///   have been timed; from then on it follows the measured time, the way
///   TCP does (RFC 6298, with Karn's rule: a message that was resent is
///   not timed). A slow preset never has a message resent before its
///   first copy has even finished sending, and a near, fast one is not
///   kept waiting for nothing.
/// - **Priority.** ACKs go before chat, and "DNet is here" goes last,
///   where the radio keeps a send queue of its own.
/// - **No doubles.** A message heard twice (a retry whose ACK was lost, a
///   copy that came round the mesh another way) is handed up once.
/// - **A hop limit**, passed to the radio, so a message cannot circle a
///   mesh for ever.
/// - **Compression** of a message that shrinks when squeezed. Sealed
///   envelopes do not, so this mostly helps the small clear-text control
///   messages, and the mock. The flag says which.
/// - **Replay protection.** Each message carries a number that only goes
///   up for its sender within one run; one numbered below the window of
///   what has been heard from that sender is dropped. This is on top of
///   the core, which signs and seals everything and drops any envelope it
///   has seen; it stops the radio layer itself being made to work twice.
/// - **Airtime.** Every packet sent is charged against a budget worked
///   out from the radio's bit rate and the region's duty cycle, and a
///   packet that would overspend waits. Nothing here can make the radio
///   break the law on its own; the user still has to pick a legal band.
///
/// Secrecy and proof of who wrote what are the core's: this layer reads
/// nothing it carries and trusts no address. See docs/RADIO.md.
class RadioProtocolConfig {
  const RadioProtocolConfig({
    this.tries = 4,
    this.firstWait = const Duration(seconds: 6),
    this.minWait = const Duration(seconds: 2),
    this.mostWait = const Duration(seconds: 60),
    this.hopLimit = 3,
    this.compress = true,
    this.reassemblyLife = const Duration(minutes: 3),
    this.mostAssembling = 32,
    this.mostMessage = 4096,
    this.dedupeWindow = 256,
    this.dutyCycle,
    this.airtimeWindow = const Duration(hours: 1),
    this.reliable = true,
  });

  /// How many times a message is sent before it is given up on, the first
  /// time counted.
  final int tries;

  /// How long to wait for an ACK before the first retry when nothing is
  /// known yet: no airtime from the radio, no round trip timed. Doubles
  /// each time, up to [mostWait] (or twice the first wait, where the
  /// radio is so slow that is longer). Slow radios need seconds, not
  /// milliseconds.
  final Duration firstWait;

  /// The shortest wait, however fast the round trips have been: a mesh
  /// has bad moments. Never more than [firstWait].
  final Duration minWait;
  final Duration mostWait;

  /// How many devices may pass a packet on.
  final int hopLimit;

  /// Whether to try squeezing each message.
  final bool compress;

  /// How long a half-received message is kept before its fragments are
  /// thrown away, and how many may be half-received at once. Both bound
  /// what a stranger can make this device hold.
  final Duration reassemblyLife;
  final int mostAssembling;

  /// The biggest message accepted, in bytes, before or after squeezing.
  final int mostMessage;

  /// How many message numbers are remembered per sender, to tell a
  /// message heard before.
  final int dedupeWindow;

  /// The share of time the radio may transmit, or null for no limit. The
  /// region sets it; see [RadioRegion.dutyCycle].
  final double? dutyCycle;

  /// Over what span the duty cycle is counted.
  final Duration airtimeWindow;

  /// Whether this layer does its own ACKs and retries. Off when the radio
  /// below already does (Meshtastic acknowledges and retries on its own),
  /// so the two do not both retry; dedupe and reassembly stay on.
  final bool reliable;
}

/// What became of a message handed to [RadioProtocol.send].
enum RadioSendState { sent, relayed, delivered, failed }

/// A message that arrived whole.
class RadioMessage {
  const RadioMessage({
    required this.from,
    required this.data,
    required this.hopsTravelled,
    this.rssi,
    this.snr,
  });

  final RadioAddress from;
  final Uint8List data;
  final int? hopsTravelled;
  final int? rssi;
  final double? snr;
}

/// One message given to the protocol to send, and how it is getting on.
class RadioSend {
  RadioSend._(this.id, this.to, this.fragments, this.priority);

  /// The protocol's number for the message; the app keeps it to match
  /// the outcome.
  final int id;
  final RadioAddress to;
  final List<Uint8List> fragments;
  final RadioPriority priority;
  final _outcome = Completer<RadioSendState>();
  RadioSendState state = RadioSendState.sent;

  /// Why it failed, in plain words, once it has.
  String? reason;

  /// When the first round was handed to the radio, to time the round
  /// trip. Only the first: an ACK after a resend could be for either.
  DateTime? _firstSentAt;

  /// Which fragments the other end has not yet confirmed.
  late final Set<int> missing = {for (var i = 0; i < fragments.length; i++) i};
  int attempt = 0;
  Timer? timer;

  /// Completes with the final state: delivered or failed. (A message sent
  /// without reliability completes as sent once the radio has taken it.)
  Future<RadioSendState> get outcome => _outcome.future;

  void _finish(RadioSendState end) {
    timer?.cancel();
    timer = null;
    state = end;
    if (!_outcome.isCompleted) _outcome.complete(end);
  }
}

/// How long round trips to one device have lately taken: a smoothed mean
/// and how much they vary (RFC 6298).
class _RoundTrip {
  _RoundTrip(Duration first)
    : mean = first.inMicroseconds.toDouble(),
      spread = first.inMicroseconds / 2;
  double mean;
  double spread;

  void add(Duration sample) {
    final r = sample.inMicroseconds.toDouble();
    spread = 0.75 * spread + 0.25 * (mean - r).abs();
    mean = 0.875 * mean + 0.125 * r;
  }

  /// The wait it suggests: the mean and four times the spread.
  Duration get wait => Duration(microseconds: (mean + 4 * spread).round());
}

/// Reads and writes the frames of this protocol. Kept apart from the
/// stateful protocol so the fuzz tests can throw bytes at it alone.
abstract final class RadioFrame {
  /// The protocol's version. A frame with another is dropped.
  static const version = 1;

  // Kinds.
  static const kindData = 1;
  static const kindAck = 2;

  // Flags on a data frame.
  static const flagCompressed = 0x01;

  /// The fixed part of a data frame: version/kind, flags, message number
  /// (2), fragment index, fragment count.
  static const dataHeader = 6;

  /// The fixed part of an ACK: version/kind, message number (2), the
  /// number of fragments still missing, then one byte per missing one.
  static const ackHeader = 4;

  static int _head(int kind) => (version << 4) | kind;

  /// A data frame carrying fragment [index] of [count] of message [id].
  static Uint8List data({
    required int id,
    required int index,
    required int count,
    required bool compressed,
    required Uint8List fragment,
  }) {
    final out = Uint8List(dataHeader + fragment.length);
    out[0] = _head(kindData);
    out[1] = compressed ? flagCompressed : 0;
    out[2] = id >> 8;
    out[3] = id & 0xFF;
    out[4] = index;
    out[5] = count;
    out.setRange(dataHeader, out.length, fragment);
    return out;
  }

  /// An ACK for message [id], naming what is still [missing]. Empty
  /// means the whole message is here.
  static Uint8List ack({required int id, required List<int> missing}) {
    final out = Uint8List(ackHeader + missing.length);
    out[0] = _head(kindAck);
    out[1] = id >> 8;
    out[2] = id & 0xFF;
    out[3] = missing.length;
    out.setRange(ackHeader, out.length, missing);
    return out;
  }

  /// Reads a frame. Null for anything that is not one of ours, however
  /// it is wrong: too short, another version, an unknown kind, counts
  /// that do not add up. Nothing here throws.
  static ParsedFrame? parse(Uint8List bytes) {
    if (bytes.length < 4) return null;
    if (bytes[0] >> 4 != version) return null;
    switch (bytes[0] & 0x0F) {
      case kindData:
        if (bytes.length < dataHeader) return null;
        final flags = bytes[1];
        if (flags & ~flagCompressed != 0) return null;
        final index = bytes[4];
        final count = bytes[5];
        if (count == 0 || index >= count) return null;
        return ParsedFrame.data(
          id: (bytes[2] << 8) | bytes[3],
          index: index,
          count: count,
          compressed: flags & flagCompressed != 0,
          fragment: Uint8List.sublistView(bytes, dataHeader),
        );
      case kindAck:
        final many = bytes[3];
        if (bytes.length != ackHeader + many) return null;
        final missing = bytes.sublist(ackHeader);
        // Each fragment named once, in order, or the frame is not ours.
        for (var i = 1; i < missing.length; i++) {
          if (missing[i] <= missing[i - 1]) return null;
        }
        return ParsedFrame.ack(
          id: (bytes[1] << 8) | bytes[2],
          missing: missing,
        );
      default:
        return null;
    }
  }
}

class ParsedFrame {
  const ParsedFrame.data({
    required this.id,
    required this.index,
    required this.count,
    required this.compressed,
    required this.fragment,
  }) : isAck = false,
       missing = const [];

  const ParsedFrame.ack({required this.id, required this.missing})
    : isAck = true,
      index = 0,
      count = 0,
      compressed = false,
      fragment = null;

  final bool isAck;
  final int id;
  final int index;
  final int count;
  final bool compressed;
  final Uint8List? fragment;
  final List<int> missing;
}

/// Squeezes with raw deflate. Returns null if that does not make it
/// smaller.
Uint8List? squeeze(Uint8List data) {
  if (data.length < 24) return null;
  final out = Uint8List.fromList(ZLibCodec(raw: true, level: 9).encode(data));
  return out.length < data.length ? out : null;
}

/// Reverses [squeeze]. Null for bytes that are not deflate, or that
/// would grow past [most].
///
/// It stops as soon as [most] is passed, rather than opening everything
/// and measuring after: a few kilobytes of deflate can open to a thousand
/// times as much, and anyone on the channel can send them.
Uint8List? unsqueeze(Uint8List data, {required int most}) {
  final opened = _Capped(most);
  try {
    final inflating = ZLibCodec(raw: true).decoder
        .startChunkedConversion(opened);
    inflating.add(data);
    inflating.close();
    return opened.bytes.takeBytes();
  } on Object {
    return null;
  }
}

/// Takes what [unsqueeze] opens, and gives up once it is too much.
class _Capped implements Sink<List<int>> {
  _Capped(this.most);

  final int most;
  final bytes = BytesBuilder();

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > most) {
      throw const FormatException('opens to more than allowed');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

/// A message being put together from fragments.
class _Assembling {
  _Assembling(this.count, this.compressed, this.startedAt);
  final int count;
  final bool compressed;
  final DateTime startedAt;
  final Map<int, Uint8List> parts = {};
  int bytes = 0;
  int? rssi;
  double? snr;
  int? hops;

  List<int> get missing => [
    for (var i = 0; i < count; i++)
      if (!parts.containsKey(i)) i,
  ];

  bool get complete => parts.length == count;

  Uint8List join() {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      out.add(parts[i]!);
    }
    return out.toBytes();
  }
}

/// Which message numbers have lately been heard from one sender.
class _Heard {
  _Heard(this.window);
  final int window;
  final List<int> ids = [];

  /// Remembers [id]. False if it was heard already, or is older than the
  /// window of what was.
  bool fresh(int id) {
    if (ids.contains(id)) return false;
    if (ids.length >= window) {
      // Behind the window: a replay of something long gone.
      final oldest = ids.first;
      if (_before(id, oldest)) return false;
      ids.removeAt(0);
    }
    ids.add(id);
    return true;
  }

  /// Whether [a] comes before [b] in a 16-bit count that wraps.
  static bool _before(int a, int b) => ((a - b) & 0xFFFF) > 0x8000;
}

/// Keeps the radio within its airtime budget.
class AirtimeBudget {
  AirtimeBudget({
    required this.dutyCycle,
    required this.window,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final double? dutyCycle;
  final Duration window;
  final DateTime Function() _clock;
  final List<(DateTime, Duration)> _spent = [];

  /// How long [bytes] take on the air at [bitsPerSecond]. LoRa adds a
  /// preamble and headers; a fifth is added for them.
  static Duration airtime(int bytes, int bitsPerSecond) => Duration(
    microseconds: (bytes * 8 * 1000000 * 1.2 / bitsPerSecond).round(),
  );

  Duration get _used {
    final now = _clock();
    _spent.removeWhere((s) => now.difference(s.$1) > window);
    return _spent.fold(Duration.zero, (sum, s) => sum + s.$2);
  }

  /// The share of the window already used.
  double get used =>
      dutyCycle == null ? 0 : _used.inMicroseconds / window.inMicroseconds;

  /// How long to wait before sending something that takes [on] on the
  /// air. Zero if it can go now.
  Duration waitFor(Duration on) {
    final limit = dutyCycle;
    if (limit == null) return Duration.zero;
    final allowed = Duration(
      microseconds: (window.inMicroseconds * limit).round(),
    );
    final used = _used;
    if (used + on <= allowed) return Duration.zero;
    // Wait until enough of the oldest spending falls out of the window.
    final now = _clock();
    var freed = Duration.zero;
    for (final (at, took) in _spent) {
      freed += took;
      if (used - freed + on <= allowed) {
        return at.add(window).difference(now);
      }
    }
    return window;
  }

  void spend(Duration on) => _spent.add((_clock(), on));
}

/// The protocol itself: one per radio.
class RadioProtocol {
  RadioProtocol(
    this.transport, {
    this.config = const RadioProtocolConfig(),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure(),
       budget = AirtimeBudget(
         dutyCycle: config.dutyCycle,
         window: config.airtimeWindow,
         clock: clock,
       ) {
    _nextId = _random.nextInt(0x10000);
  }

  final RadioTransport transport;
  final RadioProtocolConfig config;
  final AirtimeBudget budget;
  final DateTime Function() _clock;
  final Random _random;

  final _messages = StreamController<RadioMessage>.broadcast();
  final _states = StreamController<(RadioSend, RadioSendState)>.broadcast();

  /// Messages that arrived whole.
  Stream<RadioMessage> get messages => _messages.stream;

  /// Every change in how a message being sent is getting on.
  Stream<(RadioSend, RadioSendState)> get states => _states.stream;

  late int _nextId;
  final Map<int, RadioSend> _sending = {};
  final Map<(RadioAddress, int), _Assembling> _assembling = {};
  final Map<RadioAddress, _Heard> _heard = {};

  /// Round trips timed, per device.
  final Map<RadioAddress, _RoundTrip> _roundTrips = {};

  /// How many senders are remembered for dedupe at once.
  static const _mostSenders = 512;
  StreamSubscription<RadioPacket>? _listening;
  StreamSubscription<RadioDelivery>? _outcomes;

  /// The radio's packet ids of the fragments of each message, to match
  /// the radio's own word on delivery.
  final Map<int, int> _packetToSend = {};

  /// Counts, for the status screen.
  int sentPackets = 0;
  int receivedPackets = 0;
  int droppedPackets = 0;

  /// Starts listening to the radio.
  void start() {
    _listening ??= transport.received.listen(_onPacket);
    _outcomes ??= transport.deliveries.listen(_onDelivery);
  }

  /// Stops, failing every message still being sent.
  Future<void> stop() async {
    // The cancels are not waited for: a broadcast subscription's cancel
    // has nothing to wait on, and under a test's pretend clock the wait
    // never ends.
    unawaited(_listening?.cancel());
    _listening = null;
    unawaited(_outcomes?.cancel());
    _outcomes = null;
    for (final send in _sending.values.toList()) {
      _fail(send, 'stopped');
    }
    _assembling.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _states.close();
  }

  /// The most payload one fragment carries on this radio.
  int get fragmentRoom => transport.mtu - RadioFrame.dataHeader;

  /// Stops sending message [id]: nothing more of it goes on the air, not
  /// even a retry already planned. Its outcome completes as failed; no
  /// state is reported, since whoever cancels it knows. For a message
  /// that belonged to a link that has ended: a retry of it reaching the
  /// other end later would land in whatever link replaced it there.
  void cancel(int id) {
    final send = _sending.remove(id);
    if (send == null) return;
    send.reason ??= 'cancelled';
    send._finish(RadioSendState.failed);
  }

  /// The smoothed round trip to [to]: a message out and its ACK back.
  /// Null until one has been timed.
  Duration? roundTrip(RadioAddress to) {
    final trip = _roundTrips[to];
    return trip == null ? null : Duration(microseconds: trip.mean.round());
  }

  /// Sends [data] to [to]. Returns the send, whose [RadioSend.outcome]
  /// says how it ended. Throws [ArgumentError] for a message that could
  /// never fit: more than 255 fragments, or over the size limit.
  RadioSend send(
    RadioAddress to,
    Uint8List data, {
    RadioPriority priority = RadioPriority.normal,
  }) {
    if (data.length > config.mostMessage) {
      throw ArgumentError(
        'a message may be at most ${config.mostMessage} bytes',
      );
    }
    var payload = data;
    var compressed = false;
    if (config.compress) {
      final smaller = squeeze(data);
      if (smaller != null) {
        payload = smaller;
        compressed = true;
      }
    }
    final room = fragmentRoom;
    if (room < 1) throw StateError('the radio has no room for a fragment');
    final count = (payload.length / room).ceil().clamp(1, 255);
    if (payload.length > room * 255) {
      throw ArgumentError('a message may be at most ${room * 255} bytes here');
    }
    final id = _nextId;
    _nextId = (_nextId + 1) & 0xFFFF;
    final fragments = [
      for (var i = 0; i < count; i++)
        RadioFrame.data(
          id: id,
          index: i,
          count: count,
          compressed: compressed,
          fragment: Uint8List.sublistView(
            payload,
            i * room,
            min(payload.length, (i + 1) * room),
          ),
        ),
    ];
    final sending = RadioSend._(id, to, fragments, priority);
    _sending[id] = sending;
    unawaited(_attempt(sending));
    return sending;
  }

  /// Sends what is still missing of [send], then waits for the ACK.
  Future<void> _attempt(RadioSend send) async {
    if (send.state == RadioSendState.failed ||
        send.state == RadioSendState.delivered) {
      return;
    }
    send.attempt++;
    final indexes = send.missing.toList()..sort();
    for (final index in indexes) {
      if (!_sending.containsKey(send.id)) return;
      final frame = send.fragments[index];
      final packetId = _random.nextInt(0x7FFFFFFF) + 1;
      _packetToSend[packetId] = send.id;
      if (_packetToSend.length > 1024) {
        _packetToSend.remove(_packetToSend.keys.first);
      }
      try {
        await _airtime(frame.length);
        // Cancelled while it waited for airtime.
        if (!_sending.containsKey(send.id)) return;
        await transport.send(
          RadioPacket(
            to: send.to,
            data: frame,
            id: packetId,
            hopLimit: config.hopLimit,
            wantAck: !config.reliable && !send.to.isEveryone,
            priority: send.priority,
          ),
        );
        sentPackets++;
      } on RadioException catch (e) {
        _fail(send, e.message);
        return;
      } on Object catch (e) {
        _fail(send, 'the radio refused: $e');
        return;
      }
    }
    if (send.attempt == 1) send._firstSentAt = _clock();
    if (!config.reliable) {
      // The radio below answers for delivery; nothing more to wait for
      // here unless it reports.
      return;
    }
    if (send.to.isEveryone) {
      // Nobody in particular answers a broadcast.
      _finishSend(send, RadioSendState.sent);
      return;
    }
    final wait = _waitFor(send);
    send.timer?.cancel();
    send.timer = Timer(wait, () {
      if (send.attempt >= config.tries) {
        _fail(send, 'no answer after ${config.tries} tries');
      } else {
        unawaited(_attempt(send));
      }
    });
  }

  /// How long to wait for the ACK after round [RadioSend.attempt] of
  /// [send]: the first wait, doubled for each round before.
  Duration _waitFor(RadioSend send) {
    final first = firstWaitFor(send.to, send.missing.length);
    var wait = first * (1 << (send.attempt - 1).clamp(0, 10));
    final most = config.mostWait > first * 2 ? config.mostWait : first * 2;
    if (wait > most) wait = most;
    // A little jitter, so two radios that lost the same packet do not
    // retry in step for ever.
    final jitter = (wait.inMilliseconds * 0.2 * _random.nextDouble()).round();
    return wait + Duration(milliseconds: jitter);
  }

  /// How long one round of [fragments] fragments and its ACK take on the
  /// air, over one hop. Null if the radio does not say exactly: a bare
  /// bit rate is good enough to ration airtime, not to time an answer.
  Duration? _oneHop(int fragments) {
    final frame = transport.airtime(fragmentRoom + RadioFrame.dataHeader);
    final ack = transport.airtime(RadioFrame.ackHeader + 1);
    if (frame == null || ack == null) return null;
    return frame * fragments + ack;
  }

  /// The wait before the first retry of a message of [fragments]
  /// fragments to [to]. Before any round trip to [to] is timed: the
  /// airtime of the round over every hop the packets may cross, or
  /// [RadioProtocolConfig.firstWait] if that is longer or unknown. After:
  /// the timed round trip with room for how much it varies, never below
  /// [RadioProtocolConfig.minWait] or one hop's airtime.
  Duration firstWaitFor(RadioAddress to, int fragments) {
    final hop = _oneHop(fragments);
    final trip = _roundTrips[to];
    if (trip == null) {
      final crossing = hop == null ? null : hop * (config.hopLimit + 1);
      return crossing != null && crossing > config.firstWait
          ? crossing
          : config.firstWait;
    }
    var floor = config.minWait < config.firstWait
        ? config.minWait
        : config.firstWait;
    if (hop != null && hop > floor) floor = hop;
    final wait = trip.wait;
    return wait > floor ? wait : floor;
  }

  /// How long [bytes] of this protocol take on the air: the radio's own
  /// word where it gives one, else worked out from its bit rate.
  Duration? _onAir(int bytes) {
    final exact = transport.airtime(bytes);
    if (exact != null) return exact;
    final rate = transport.bitsPerSecond;
    if (rate == null || rate <= 0) return null;
    return AirtimeBudget.airtime(bytes, rate);
  }

  Future<void> _airtime(int bytes) async {
    final on = _onAir(bytes);
    if (on == null) return;
    final wait = budget.waitFor(on);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    budget.spend(on);
  }

  void _timeRoundTrip(RadioSend send) {
    final at = send._firstSentAt;
    if (at == null || send.attempt != 1) return;
    final took = _clock().difference(at);
    if (took.isNegative) return;
    final trip = _roundTrips[send.to];
    if (trip == null) {
      if (_roundTrips.length >= 64) {
        _roundTrips.remove(_roundTrips.keys.first);
      }
      _roundTrips[send.to] = _RoundTrip(took);
    } else {
      trip.add(took);
    }
  }

  void _fail(RadioSend send, String why) {
    _sending.remove(send.id);
    send.reason ??= why;
    send._finish(RadioSendState.failed);
    _states.add((send, RadioSendState.failed));
  }

  void _finishSend(RadioSend send, RadioSendState end) {
    _sending.remove(send.id);
    send._finish(end);
    _states.add((send, end));
  }

  void _onDelivery(RadioDelivery delivery) {
    final id = _packetToSend[delivery.packetId];
    if (id == null) return;
    final send = _sending[id];
    if (send == null) return;
    switch (delivery.state) {
      case RadioDeliveryState.sent:
        break;
      case RadioDeliveryState.relayed:
        if (send.state == RadioSendState.sent) {
          send.state = RadioSendState.relayed;
          _states.add((send, RadioSendState.relayed));
        }
      case RadioDeliveryState.delivered:
        // The radio's word for one fragment. For a message of several
        // this is relayed at best: all must get there.
        if (send.fragments.length == 1) {
          _finishSend(send, RadioSendState.delivered);
        } else if (send.state == RadioSendState.sent) {
          send.state = RadioSendState.relayed;
          _states.add((send, RadioSendState.relayed));
        }
      case RadioDeliveryState.failed:
        _fail(send, delivery.reason ?? 'the radio could not deliver it');
    }
  }

  void _onPacket(RadioPacket packet) {
    receivedPackets++;
    final frame = RadioFrame.parse(packet.data);
    final from = packet.from;
    if (frame == null || from == null || from == transport.myAddress) {
      droppedPackets++;
      return;
    }
    if (frame.isAck) {
      _onAck(from, frame);
    } else {
      _onData(from, frame, packet);
    }
  }

  void _onAck(RadioAddress from, ParsedFrame ack) {
    final send = _sending[ack.id];
    if (send == null || send.to != from) return;
    _timeRoundTrip(send);
    // Timed once: whatever comes after is for a resend.
    send._firstSentAt = null;
    if (ack.missing.isEmpty) {
      _finishSend(send, RadioSendState.delivered);
      return;
    }
    send.missing
      ..clear()
      ..addAll(ack.missing.where((i) => i < send.fragments.length));
    if (send.missing.isEmpty) {
      _finishSend(send, RadioSendState.delivered);
      return;
    }
    // They have most of it: send the rest now, not after the wait.
    send.timer?.cancel();
    unawaited(_attempt(send));
  }

  void _onData(RadioAddress from, ParsedFrame data, RadioPacket packet) {
    final fragment = data.fragment!;
    if (fragment.isEmpty || fragment.length > fragmentRoom + 64) {
      droppedPackets++;
      return;
    }
    final key = (from, data.id);
    var assembling = _assembling[key];
    if (assembling == null) {
      if (!_heard.containsKey(from) && _heard.length >= _mostSenders) {
        // The longest-unheard sender makes room. Forgetting one only
        // means its next message is taken fresh.
        _heard.remove(_heard.keys.first);
      }
      final heard = _heard.putIfAbsent(from, () => _Heard(config.dedupeWindow));
      if (!heard.fresh(data.id)) {
        // Heard before, or a replay. Answer again so a lost ACK is made
        // good, but hand nothing up.
        droppedPackets++;
        if (config.reliable) _ack(from, data.id, const []);
        return;
      }
      _tidy();
      if (_assembling.length >= config.mostAssembling) {
        droppedPackets++;
        return;
      }
      assembling = _Assembling(data.count, data.compressed, _clock());
      _assembling[key] = assembling;
    } else if (assembling.count != data.count ||
        assembling.compressed != data.compressed) {
      // The same number used for something else. Not ours to guess.
      droppedPackets++;
      return;
    }
    if (!assembling.parts.containsKey(data.index)) {
      assembling.bytes += fragment.length;
      if (assembling.bytes > config.mostMessage) {
        _assembling.remove(key);
        droppedPackets++;
        return;
      }
      assembling.parts[data.index] = Uint8List.fromList(fragment);
    }
    assembling.rssi = packet.rssi ?? assembling.rssi;
    assembling.snr = packet.snr ?? assembling.snr;
    assembling.hops = packet.hopsTravelled ?? assembling.hops;
    if (!assembling.complete) {
      // Say what is still missing once the last fragment of a round has
      // gone by, which is when the sender's highest index arrives.
      if (config.reliable && data.index == data.count - 1) {
        _ack(from, data.id, assembling.missing);
      }
      return;
    }
    _assembling.remove(key);
    if (config.reliable) _ack(from, data.id, const []);
    var whole = assembling.join();
    if (assembling.compressed) {
      final opened = unsqueeze(whole, most: config.mostMessage);
      if (opened == null) {
        droppedPackets++;
        return;
      }
      whole = opened;
    }
    _messages.add(
      RadioMessage(
        from: from,
        data: whole,
        hopsTravelled: assembling.hops,
        rssi: assembling.rssi,
        snr: assembling.snr,
      ),
    );
  }

  void _ack(RadioAddress to, int id, List<int> missing) {
    final frame = RadioFrame.ack(id: id, missing: missing);
    unawaited(() async {
      try {
        await _airtime(frame.length);
        await transport.send(
          RadioPacket(
            to: to,
            data: frame,
            hopLimit: config.hopLimit,
            priority: RadioPriority.high,
          ),
        );
        sentPackets++;
      } on Object {
        // The radio is gone. The sender will try again or give up.
      }
    }());
  }

  /// Throws away half-received messages nobody has added to for a while.
  void _tidy() {
    final now = _clock();
    _assembling.removeWhere(
      (_, a) => now.difference(a.startedAt) > config.reassemblyLife,
    );
  }
}
