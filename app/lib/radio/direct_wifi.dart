import 'dart:math';

import 'package:flutter/services.dart';

/// A Wi-Fi Direct group: a small Wi-Fi network one device makes for
/// another to join. It needs no router, no hotspot and no internet, and
/// lasts only as long as the two want it.
///
/// It is only a road between two devices. Everything that travels on it
/// is sealed by the core exactly as it is over Bluetooth, so its password
/// keeps strangers off the road; it is not what keeps messages private.
class DirectGroup {
  const DirectGroup(this.network, this.pass);

  /// A group nobody has used before, with a name and password made up on
  /// the spot. Android will only join a group whose name starts this way.
  factory DirectGroup.fresh([Random? random]) {
    final dice = random ?? Random.secure();
    String made(String from, int length) =>
        [for (var i = 0; i < length; i++) from[dice.nextInt(from.length)]]
            .join();
    const lower = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const mixed = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ$lower';
    return DirectGroup('DIRECT-dN-${made(lower, 8)}', made(mixed, 20));
  }

  final String network;
  final String pass;

  @override
  bool operator ==(Object other) =>
      other is DirectGroup && other.network == network && other.pass == pass;

  @override
  int get hashCode => Object.hash(network, pass);
}

/// The two Wi-Fi bands a group can be made on.
enum WifiBand {
  /// 2.4 GHz: reaches further, and is the more crowded.
  low('2.4'),

  /// 5 GHz: faster, shorter reach, mostly quieter.
  high('5');

  const WifiBand(this.wire);

  /// How the device names it.
  final String wire;

  WifiBand get other => this == low ? high : low;
}

/// What a device can do with Wi-Fi Direct. A phone can make a group or
/// join one. A PC can make one for a phone to join.
abstract class DirectWifi {
  /// Whether this device can join a group another device made.
  bool get canJoin;

  /// Whether this device can choose the band a group it makes is on.
  /// Android can. Windows makes its group wherever it likes, and says
  /// nothing of which.
  bool get canChooseBand;

  /// Makes [group] for another device to join, on [band] if one is given
  /// and the device can choose. False if it could not: Wi-Fi is off, the
  /// user did not allow it, the device has none, or not on that band.
  Future<bool> host(DirectGroup group, {WifiBand? band});

  /// Which band is the quieter here: the one with fewer Wi-Fi networks
  /// heard, the loud ones counting double. Null where the device cannot
  /// tell, or has only one band.
  Future<WifiBand?> quieterBand();

  /// Joins a group another device made. Returns the address of that
  /// device on the group's network, or null if it could not.
  Future<String?> join(DirectGroup group);

  /// On the device that made the group: the addresses of the devices that
  /// have joined, where the device can tell. Android cannot.
  Future<List<String>> members();

  /// Gives up whatever group this device made or joined.
  Future<void> leave();
}

/// Wi-Fi Direct on Android, done in Kotlin in `WifiDirect.kt`.
///
/// Not yet verified on devices.
class ChannelDirectWifi implements DirectWifi {
  // Must match the channel name in MainActivity.kt.
  static const _channel = MethodChannel('dnet/direct');

  Future<T?> _ask<T>(
    String method, [
    DirectGroup? group,
    WifiBand? band,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, {
        'network': ?group?.network,
        'pass': ?group?.pass,
        'band': ?band?.wire,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  bool get canJoin => true;

  @override
  bool get canChooseBand => true;

  @override
  Future<bool> host(DirectGroup group, {WifiBand? band}) async =>
      await _ask<bool>('host', group, band) ?? false;

  @override
  Future<WifiBand?> quieterBand() async =>
      switch (await _ask<String>('quieter_band')) {
        final String wire =>
          WifiBand.values.where((band) => band.wire == wire).firstOrNull,
        null => null,
      };

  @override
  Future<String?> join(DirectGroup group) => _ask<String>('join', group);

  @override
  Future<List<String>> members() async => const [];

  @override
  Future<void> leave() => _ask<void>('leave');
}

/// Wi-Fi Direct on Windows, done in Rust in `radio_windows/src/direct.rs`.
/// A PC makes a group for a phone to join. It does not join one: that
/// would take it off whatever Wi-Fi it is on.
///
/// Not yet verified on devices.
class LibraryDirectWifi implements DirectWifi {
  LibraryDirectWifi(this._call);

  /// One request to the radio library, answered at once.
  final Object? Function(Map<String, Object?> request) _call;

  Object? _ask(Map<String, Object?> request) {
    try {
      return _call(request);
    } on Exception {
      return null;
    }
  }

  @override
  bool get canJoin => false;

  /// Windows has no way to ask for a band for a group it makes.
  @override
  bool get canChooseBand => false;

  @override
  Future<WifiBand?> quieterBand() async => null;

  @override
  Future<bool> host(DirectGroup group, {WifiBand? band}) async {
    final started = _ask({
      'op': 'direct_host',
      'network': group.network,
      'pass': group.pass,
    });
    if (started != true) return false;
    // Windows says a moment later whether it really began.
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      switch (_ask({'op': 'direct_state'})) {
        case {'state': 'on'}:
          return true;
        case {'state': 'starting'}:
          continue;
        default:
          return false;
      }
    }
    _ask({'op': 'direct_stop'});
    return false;
  }

  @override
  Future<String?> join(DirectGroup group) async => null;

  @override
  Future<List<String>> members() async =>
      switch (_ask({'op': 'direct_state'})) {
        {'state': 'on', 'members': final List<Object?> members} =>
          members.whereType<String>().toList(),
        _ => const [],
      };

  @override
  Future<void> leave() async => _ask({'op': 'direct_stop'});
}
