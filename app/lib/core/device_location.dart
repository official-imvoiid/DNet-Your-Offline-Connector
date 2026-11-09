import 'dart:async';

import 'package:flutter/services.dart';

import '../data/place.dart';

/// What the device said, as a place or a reason there is none.
Located _read(Object? reply) {
  if (reply is! Map) return const Located.not(NoPlace.unknown);
  return switch (reply['state']) {
    'ok' => switch (Place.fromWire({
      'lat': reply['lat'],
      'lon': reply['lon'],
      // Rounded up: "within 12.3 m" is within 13 m, not 12.
      'accuracy': switch (reply['accuracy']) {
        final num metres => metres.ceil(),
        _ => 0,
      },
    })) {
      final place? => Located.at(place),
      null => const Located.not(NoPlace.unknown),
    },
    'denied' => const Located.not(NoPlace.denied),
    'off' || 'off_here' => const Located.not(NoPlace.off),
    _ => const Located.not(NoPlace.unknown),
  };
}

/// Android's own location service, through the app's Kotlin side. Works
/// from GPS with no internet and with no Google services.
///
/// Not yet verified on devices.
class ChannelLocator implements Locator {
  // Must match the channel name in MainActivity.kt.
  static const _channel = MethodChannel('dnet/location');

  @override
  Future<Located> locate() async {
    try {
      return _read(await _channel.invokeMethod<Object?>('find'));
    } on PlatformException {
      return const Located.not(NoPlace.unknown);
    } on MissingPluginException {
      return const Located.not(NoPlace.unknown);
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('settings');
    } on PlatformException {
      // Nothing to open. The words on screen say where to go.
    } on MissingPluginException {
      // The same.
    }
  }

  @override
  Future<bool> openMap(Place place) async {
    try {
      return await _channel.invokeMethod<bool>('openMap', {
            'lat': place.lat,
            'lon': place.lon,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// A `geo:` place opens in whatever map app the user has.
  @override
  bool get mapsInBrowser => false;
}

/// Windows' location service, through the same library as the radio. It
/// answers the way the core does, and in its own time, so the app asks
/// and then looks for the answer.
///
/// Not yet verified on devices.
class LibraryLocator implements Locator {
  LibraryLocator(this._call, {this.patience = const Duration(seconds: 40)});

  final Object? Function(Map<String, Object?> request) _call;

  /// How long to wait for Windows before giving up. Windows itself gives
  /// up a little sooner.
  final Duration patience;

  Object? _ask(Map<String, Object?> request) {
    try {
      return _call(request);
    } on Exception {
      return null;
    }
  }

  @override
  Future<Located> locate() async {
    _ask({'op': 'location_start'});
    final until = DateTime.now().add(patience);
    try {
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final state = _ask({'op': 'location_state'});
        if (state is Map && state['state'] == 'busy') continue;
        return _read(state);
      }
      return const Located.not(NoPlace.unknown);
    } finally {
      // The place is not kept in the library once the app has it.
      _ask({'op': 'location_stop'});
    }
  }

  @override
  Future<void> openSettings() async => _ask({'op': 'location_settings'});

  @override
  Future<bool> openMap(Place place) async =>
      _ask({'op': 'open_map', 'url': place.webMap}) == true;

  /// A PC has no map app the app can count on, so a map is a web page.
  @override
  bool get mapsInBrowser => true;
}
