import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// One interface for every kind of long-range radio the app can plug in:
/// a Meshtastic device over Bluetooth, USB or Wi-Fi, a bare LoRa module
/// behind a serial port, or the mock used by tests and demos.
///
/// A radio transport moves small packets (a LoRa packet is about 200
/// bytes) between this device and others on the same frequency. It knows
/// nothing about who anyone is and reads nothing it carries. Everything
/// above it is end-to-end sealed by the core before it gets here, so the
/// radio's own encryption, where it has any, is treated as nothing.
///
/// What a driver must give: connect, disconnect, send, a stream of what
/// arrives, the link's status, how well the other end is heard, who the
/// device is, and the most one packet can carry.
abstract class RadioTransport {
  /// Opens the device. Throws [RadioException] if it cannot be opened.
  Future<void> connect();

  /// Closes the device. Safe to call twice.
  Future<void> disconnect();

  /// Sends one packet to [to], or to everyone in range with
  /// [RadioAddress.everyone]. The packet must be at most [mtu] bytes.
  /// Completes when the device has taken it, not when it has arrived.
  Future<void> send(RadioPacket packet);

  /// Every packet heard, as it arrives.
  Stream<RadioPacket> get received;

  /// The link's status as it changes, starting with its state now.
  Stream<RadioLinkStatus> get status;

  /// The status this moment.
  RadioLinkStatus get linkStatus;

  /// How strongly and how cleanly the last packets were heard, by the
  /// address they came from, as each arrives.
  Stream<RadioSignal> get signals;

  /// What the device says it is. Null until connected.
  RadioDeviceInfo? get device;

  /// The most bytes one packet may carry, once connected. Before that,
  /// the driver's safe guess.
  int get mtu;

  /// This device's own address on the radio, once known.
  RadioAddress? get myAddress;

  /// Outcomes of packets sent with [RadioPacket.wantAck]: whether each got
  /// to the other end, as the radio or the mesh reports it.
  Stream<RadioDelivery> get deliveries;

  /// Sets the region: which band the radio transmits on. The user chooses
  /// it; the app never guesses. Throws [RadioException] if the device
  /// refuses it.
  Future<void> setRegion(RadioRegion region);

  /// How many bits a second the radio sends at with its present settings,
  /// so airtime can be budgeted. Null if the device does not say.
  int? get bitsPerSecond;

  /// How long one packet carrying [bytes] of the app's data stays on the
  /// air, the radio's own headers and preamble included. Null if the
  /// driver cannot tell; [bitsPerSecond] is the rougher fallback.
  Duration? airtime(int bytes);
}

/// The settings a LoRa radio sends with, and how long a packet takes on
/// the air with them. The time is Semtech's formula (AN1200.13, "LoRa
/// Modem Designer's Guide"): a preamble, a header, then the payload in
/// blocks of symbols, each symbol lasting 2^SF / bandwidth seconds.
@immutable
class LoraModem {
  const LoraModem({
    required this.spreadingFactor,
    required this.bandwidthHz,
    required this.codingRate,
    this.preambleSymbols = 16,
    this.crc = true,
  });

  /// 7 (fast, short reach) to 12 (slow, far).
  final int spreadingFactor;
  final int bandwidthHz;

  /// The second number of the coding rate: 5 for 4/5 up to 8 for 4/8.
  final int codingRate;

  /// Meshtastic sends 16; LoRaWAN 8.
  final int preambleSymbols;
  final bool crc;

  double get _symbolSeconds => (1 << spreadingFactor) / bandwidthHz;

  /// Radios switch on low data-rate optimisation once a symbol lasts
  /// 16 ms or more, which makes every block carry fewer bits.
  bool get lowDataRate => _symbolSeconds >= 0.016;

  int get bitsPerSecond =>
      (spreadingFactor * bandwidthHz / (1 << spreadingFactor) * 4 / codingRate)
          .round();

  /// How long a packet of [payloadBytes] (everything after the LoRa
  /// header: the radio firmware's own header included) is on the air.
  Duration airtime(int payloadBytes) {
    final sf = spreadingFactor;
    final de = lowDataRate ? 1 : 0;
    final bits = 8 * payloadBytes - 4 * sf + 28 + (crc ? 16 : 0);
    final blocks = bits <= 0 ? 0 : (bits / (4 * (sf - 2 * de))).ceil();
    final symbols = preambleSymbols + 4.25 + 8 + blocks * codingRate;
    return Duration(microseconds: (symbols * _symbolSeconds * 1e6).round());
  }

  @override
  bool operator ==(Object other) =>
      other is LoraModem &&
      other.spreadingFactor == spreadingFactor &&
      other.bandwidthHz == bandwidthHz &&
      other.codingRate == codingRate &&
      other.preambleSymbols == preambleSymbols &&
      other.crc == crc;

  @override
  int get hashCode => Object.hash(
    spreadingFactor,
    bandwidthHz,
    codingRate,
    preambleSymbols,
    crc,
  );

  @override
  String toString() =>
      'SF$spreadingFactor ${bandwidthHz / 1000} kHz 4/$codingRate';
}

/// Which packets a radio should send first when several wait. Meshtastic
/// keeps its send queue in this order; a radio without a queue of its own
/// ignores it.
enum RadioPriority {
  /// "DNet is here" and other things that can wait.
  background,

  /// Chat.
  normal,

  /// Answers the other end is waiting on: acknowledgements.
  high,
}

/// A device could not be opened or used.
class RadioException implements Exception {
  const RadioException(this.message, {this.permanent = false});

  final String message;

  /// True when trying again will not help: the device is unsupported, or
  /// the user has refused permission for good.
  final bool permanent;

  @override
  String toString() => 'RadioException: $message';
}

/// Where a packet is going, or came from: a node number on the radio.
/// Meshtastic nodes have 32-bit numbers; serial modules are given one.
class RadioAddress {
  const RadioAddress(this.node);

  /// Everyone in range.
  static const everyone = RadioAddress(0xFFFFFFFF);

  final int node;

  bool get isEveryone => node == everyone.node;

  @override
  bool operator ==(Object other) => other is RadioAddress && other.node == node;

  @override
  int get hashCode => node.hashCode;

  @override
  String toString() =>
      isEveryone ? 'everyone' : '!${node.toRadixString(16).padLeft(8, '0')}';
}

/// One packet on the radio.
class RadioPacket {
  RadioPacket({
    required this.to,
    required this.data,
    this.from,
    this.id = 0,
    this.hopLimit = 3,
    this.wantAck = false,
    this.priority = RadioPriority.normal,
    this.rssi,
    this.snr,
    this.hopsTravelled,
  });

  final RadioAddress to;

  /// Where it goes in the radio's own send queue, where it has one.
  final RadioPriority priority;

  /// Who sent it. Set on packets received; ignored when sending.
  final RadioAddress? from;
  final Uint8List data;

  /// The radio's own number for the packet, where it has one. Zero to
  /// let the driver choose.
  final int id;

  /// How many more devices may pass it on.
  final int hopLimit;

  /// Whether the radio is asked to say when it arrived.
  final bool wantAck;

  /// How the packet was heard, for packets received.
  final int? rssi;
  final double? snr;

  /// How many devices passed it on before it got here, where known.
  final int? hopsTravelled;

  @override
  String toString() =>
      'RadioPacket(${from ?? '?'} -> $to, ${data.length} bytes, id $id)';
}

/// Whether the device is usable.
enum RadioLinkState {
  /// Not asked to connect.
  disconnected,

  /// Opening the device, or waiting for it to come back.
  connecting,

  /// The device is open and answering.
  connected,

  /// The device went away; the driver is trying again.
  reconnecting,

  /// The device could not be used. [RadioLinkStatus.reason] says why.
  failed,
}

class RadioLinkStatus {
  const RadioLinkStatus(this.state, {this.reason, this.permanent = false});

  final RadioLinkState state;

  /// Why, when [state] is [RadioLinkState.failed].
  final String? reason;

  /// Whether trying again is pointless.
  final bool permanent;

  bool get isUp => state == RadioLinkState.connected;

  @override
  bool operator ==(Object other) =>
      other is RadioLinkStatus &&
      other.state == state &&
      other.reason == reason &&
      other.permanent == permanent;

  @override
  int get hashCode => Object.hash(state, reason, permanent);

  @override
  String toString() =>
      'RadioLinkStatus($state${reason == null ? '' : ': $reason'})';
}

/// How well a device was heard: the signal's strength in dBm (-40 very
/// loud, -120 at the edge) and how far above the noise it was, in dB.
class RadioSignal {
  const RadioSignal({required this.from, this.rssi, this.snr});

  final RadioAddress from;
  final int? rssi;
  final double? snr;

  /// One of four words for the signal: strong, good, weak, faint. LoRa
  /// hears far below the noise, so SNR counts for as much as strength.
  SignalGrade get grade {
    final r = rssi;
    final s = snr;
    if (r == null && s == null) return SignalGrade.unknown;
    final byRssi = r == null
        ? 3
        : r >= -90
        ? 3
        : r >= -105
        ? 2
        : r >= -118
        ? 1
        : 0;
    final bySnr = s == null
        ? 3
        : s >= 5
        ? 3
        : s >= -5
        ? 2
        : s >= -15
        ? 1
        : 0;
    return SignalGrade.values[byRssi < bySnr ? byRssi : bySnr];
  }
}

enum SignalGrade { faint, weak, good, strong, unknown }

/// What the device says about itself.
class RadioDeviceInfo {
  const RadioDeviceInfo({
    required this.kind,
    required this.name,
    this.hardware,
    this.firmware,
    this.address,
    this.region,
    this.preset,
    this.modem,
    this.notice,
    this.queueFree,
  });

  /// The bandwidth, spreading factor and coding rate it sends with, where
  /// known.
  final LoraModem? modem;

  /// The last thing the device asked the user be told, in its own words,
  /// such as "Duty cycle limit exceeded. You can send again in 12 mins".
  final String? notice;

  /// How many more packets its send queue can take, where it says.
  final int? queueFree;

  /// Which driver speaks to it.
  final RadioDriverKind kind;

  /// The name shown to the user: the node's long name, the port, or
  /// "Mock".
  final String name;

  /// The board, as the device reports it, where it does.
  final String? hardware;
  final String? firmware;
  final RadioAddress? address;

  /// The region the device says it is set to, where it says.
  final String? region;

  /// The modem preset (bandwidth, spreading factor) by name, where known.
  final String? preset;
}

/// The kinds of driver the app has.
enum RadioDriverKind {
  /// A Meshtastic device, by any of its three connections.
  meshtastic,

  /// A bare LoRa module behind DNet's serial framing.
  serialLora,

  /// The loopback used by tests and demos.
  mock,
}

/// What became of a packet sent with an acknowledgement asked for.
enum RadioDeliveryState {
  /// Handed to the radio; nothing heard back yet.
  sent,

  /// A device in between confirmed it is carrying it on, but the one it
  /// is for has not yet said it has it.
  relayed,

  /// The device it is for has it.
  delivered,

  /// Every try failed, or the radio said it could not be delivered.
  failed,
}

class RadioDelivery {
  const RadioDelivery(this.packetId, this.state, {this.reason});

  /// The id the packet was sent with.
  final int packetId;
  final RadioDeliveryState state;
  final String? reason;

  @override
  String toString() => 'RadioDelivery($packetId: $state)';
}

/// A band the radio may use. Which one is legal depends on the country,
/// and the user must choose: the app never guesses from anything.
class RadioRegion {
  const RadioRegion({
    required this.code,
    required this.name,
    required this.mhzLow,
    required this.mhzHigh,
    required this.countries,
    this.dutyCycle,
    this.maxPowerDbm,
    this.meshtasticCode,
    this.note,
    this.maxBandwidthKhz,
  });

  /// The widest signal the rules allow, where they set one. A modem preset
  /// wider than this is outside them even on the right frequencies.
  final int? maxBandwidthKhz;

  /// The app's own code, such as "IN".
  final String code;
  final String name;
  final double mhzLow;
  final double mhzHigh;

  /// Where it is legal, in words.
  final String countries;

  /// The share of time the radio may transmit, where the law sets one.
  /// Null: no duty-cycle limit (other rules may still apply).
  final double? dutyCycle;
  final int? maxPowerDbm;

  /// The Meshtastic region enum value the device is set to, where one
  /// matches.
  final int? meshtasticCode;
  final String? note;

  /// The regions the app offers. The user must pick the one that is
  /// legal where they are; see docs/RADIO.md.
  static const all = [
    RadioRegion(
      code: 'IN',
      name: 'India 865–867 MHz',
      mhzLow: 865,
      mhzHigh: 867,
      countries: 'India',
      maxPowerDbm: 30,
      maxBandwidthKhz: 200,
      meshtasticCode: 10,
      note:
          'Licence-free: 1 W transmitter power, 4 W ERP, 200 kHz carrier '
          'bandwidth.',
    ),
    RadioRegion(
      code: 'EU_868',
      name: 'Europe 868 MHz',
      mhzLow: 869.4,
      mhzHigh: 869.65,
      countries: 'EU, UK, and most of Europe',
      dutyCycle: 0.10,
      maxPowerDbm: 27,
      meshtasticCode: 3,
      note: 'The 869.4–869.65 MHz sub-band allows 10% airtime at 500 mW.',
    ),
    RadioRegion(
      code: 'EU_433',
      name: 'Europe 433 MHz',
      mhzLow: 433.05,
      mhzHigh: 434.79,
      countries: 'EU and most of Europe',
      dutyCycle: 0.10,
      maxPowerDbm: 10,
      meshtasticCode: 2,
      note: '10 mW only. Short range; use 868 where you can.',
    ),
    RadioRegion(
      code: 'US',
      name: 'Americas 915 MHz',
      mhzLow: 902,
      mhzHigh: 928,
      countries: 'USA, Canada, Mexico, most of the Americas',
      maxPowerDbm: 30,
      meshtasticCode: 1,
      note: 'No duty cycle; 400 ms dwell per channel.',
    ),
    RadioRegion(
      code: 'BR_902',
      name: 'Brazil 902 MHz',
      mhzLow: 902,
      mhzHigh: 907.5,
      countries: 'Brazil',
      maxPowerDbm: 30,
      meshtasticCode: 26,
    ),
    RadioRegion(
      code: 'ANZ',
      name: 'Australia / NZ 915 MHz',
      mhzLow: 915,
      mhzHigh: 928,
      countries: 'Australia, New Zealand',
      maxPowerDbm: 30,
      meshtasticCode: 6,
    ),
    RadioRegion(
      code: 'ANZ_433',
      name: 'Australia / NZ 433 MHz',
      mhzLow: 433.05,
      mhzHigh: 434.79,
      countries: 'Australia, New Zealand',
      maxPowerDbm: 14,
      meshtasticCode: 22,
    ),
    RadioRegion(
      code: 'NZ_865',
      name: 'New Zealand 865 MHz',
      mhzLow: 864,
      mhzHigh: 868,
      countries: 'New Zealand',
      maxPowerDbm: 36,
      meshtasticCode: 11,
    ),
    RadioRegion(
      code: 'JP',
      name: 'Japan 920 MHz',
      mhzLow: 920.5,
      mhzHigh: 923.5,
      countries: 'Japan',
      dutyCycle: 0.10,
      maxPowerDbm: 13,
      meshtasticCode: 5,
      note:
          'ARIB STD-T108: listen before sending, short transmissions. '
          'DNet keeps itself to 10% airtime here.',
    ),
    RadioRegion(
      code: 'KR',
      name: 'Korea 920 MHz',
      mhzLow: 920,
      mhzHigh: 923,
      countries: 'South Korea',
      maxPowerDbm: 23,
      meshtasticCode: 7,
    ),
    RadioRegion(
      code: 'TW',
      name: 'Taiwan 923 MHz',
      mhzLow: 920,
      mhzHigh: 925,
      countries: 'Taiwan',
      maxPowerDbm: 27,
      meshtasticCode: 8,
    ),
    RadioRegion(
      code: 'CN',
      name: 'China 470 MHz',
      mhzLow: 470,
      mhzHigh: 510,
      countries: 'China',
      maxPowerDbm: 19,
      meshtasticCode: 4,
    ),
    RadioRegion(
      code: 'RU',
      name: 'Russia 868 MHz',
      mhzLow: 868.7,
      mhzHigh: 869.2,
      countries: 'Russia',
      maxPowerDbm: 20,
      meshtasticCode: 9,
    ),
    RadioRegion(
      code: 'TH',
      name: 'Thailand 920 MHz',
      mhzLow: 920,
      mhzHigh: 925,
      countries: 'Thailand',
      dutyCycle: 0.10,
      maxPowerDbm: 27,
      meshtasticCode: 12,
    ),
    RadioRegion(
      code: 'MY_919',
      name: 'Malaysia 919 MHz',
      mhzLow: 919,
      mhzHigh: 924,
      countries: 'Malaysia',
      maxPowerDbm: 27,
      meshtasticCode: 17,
    ),
    RadioRegion(
      code: 'MY_433',
      name: 'Malaysia 433 MHz',
      mhzLow: 433,
      mhzHigh: 435,
      countries: 'Malaysia',
      maxPowerDbm: 20,
      meshtasticCode: 16,
    ),
    RadioRegion(
      code: 'SG',
      name: 'Singapore 923 MHz',
      mhzLow: 917,
      mhzHigh: 925,
      countries: 'Singapore',
      maxPowerDbm: 20,
      meshtasticCode: 18,
    ),
    RadioRegion(
      code: 'PH_915',
      name: 'Philippines 915 MHz',
      mhzLow: 915,
      mhzHigh: 918,
      countries: 'Philippines',
      maxPowerDbm: 24,
      meshtasticCode: 21,
    ),
    RadioRegion(
      code: 'PH_868',
      name: 'Philippines 868 MHz',
      mhzLow: 868,
      mhzHigh: 869.4,
      countries: 'Philippines',
      maxPowerDbm: 14,
      meshtasticCode: 20,
    ),
    RadioRegion(
      code: 'PH_433',
      name: 'Philippines 433 MHz',
      mhzLow: 433,
      mhzHigh: 434.7,
      countries: 'Philippines',
      maxPowerDbm: 10,
      meshtasticCode: 19,
    ),
    RadioRegion(
      code: 'NP_865',
      name: 'Nepal 865 MHz',
      mhzLow: 865,
      mhzHigh: 868,
      countries: 'Nepal',
      maxPowerDbm: 30,
      meshtasticCode: 25,
    ),
    RadioRegion(
      code: 'KZ_863',
      name: 'Kazakhstan 863 MHz',
      mhzLow: 863,
      mhzHigh: 868,
      countries: 'Kazakhstan',
      maxPowerDbm: 30,
      meshtasticCode: 24,
    ),
    RadioRegion(
      code: 'KZ_433',
      name: 'Kazakhstan 433 MHz',
      mhzLow: 433.075,
      mhzHigh: 434.775,
      countries: 'Kazakhstan',
      maxPowerDbm: 10,
      meshtasticCode: 23,
    ),
    RadioRegion(
      code: 'UA_868',
      name: 'Ukraine 868 MHz',
      mhzLow: 868,
      mhzHigh: 868.6,
      countries: 'Ukraine',
      dutyCycle: 0.01,
      maxPowerDbm: 14,
      meshtasticCode: 15,
    ),
    RadioRegion(
      code: 'UA_433',
      name: 'Ukraine 433 MHz',
      mhzLow: 433,
      mhzHigh: 434.7,
      countries: 'Ukraine',
      dutyCycle: 0.10,
      maxPowerDbm: 10,
      meshtasticCode: 14,
    ),
    RadioRegion(
      code: 'LORA_24',
      name: '2.4 GHz LoRa',
      mhzLow: 2400,
      mhzHigh: 2483.5,
      countries: 'Most countries, with a 2.4 GHz LoRa board only',
      maxPowerDbm: 10,
      meshtasticCode: 13,
      note: 'Needs a 2.4 GHz board (SX128x). Short range indoors.',
    ),
  ];

  /// The region for an app code, or null.
  static RadioRegion? byCode(String code) =>
      all.where((r) => r.code == code).firstOrNull;

  @override
  String toString() => code;
}
