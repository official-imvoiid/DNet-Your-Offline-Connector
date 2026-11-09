import 'package:flutter/foundation.dart';

/// A place on Earth someone chose to send: degrees north and east, and
/// how far off their device said it might be. The app never looks a place
/// up, draws a map of it or sends it anywhere the user did not choose.
@immutable
class Place {
  const Place(this.lat, this.lon, {this.accuracy = 0});

  final double lat;
  final double lon;

  /// In metres. Nought: the device did not say.
  final int accuracy;

  /// Whether this is a place at all: on the globe, and found to within
  /// 100 km. The core holds every place to the same.
  bool get sound =>
      lat.isFinite &&
      lon.isFinite &&
      lat.abs() <= 90 &&
      lon.abs() <= 180 &&
      accuracy >= 0 &&
      accuracy <= 100000;

  String _degrees(double value) => value.toStringAsFixed(6);

  /// The place in words: "51.500729, -0.124625". This is what is copied.
  String get text => '${_degrees(lat)}, ${_degrees(lon)}';

  /// The place on OpenStreetMap, in a browser. Built only from the two
  /// numbers, so it cannot lead anywhere else.
  String get webMap {
    final (n, e) = (_degrees(lat), _degrees(lon));
    return 'https://www.openstreetmap.org/?mlat=$n&mlon=$e#map=17/$n/$e';
  }

  /// What the core is given and gives back.
  Map<String, Object> toWire() => {
    'lat': lat,
    'lon': lon,
    'accuracy': accuracy,
  };

  /// A place as the core gives it, or null if [wire] is not one.
  static Place? fromWire(Object? wire) {
    if (wire case {'lat': final num lat, 'lon': final num lon}) {
      final place = Place(
        lat.toDouble(),
        lon.toDouble(),
        accuracy: switch (wire['accuracy']) {
          final num metres => metres.round(),
          _ => 0,
        },
      );
      return place.sound ? place : null;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.lat == lat &&
      other.lon == lon &&
      other.accuracy == accuracy;

  @override
  int get hashCode => Object.hash(lat, lon, accuracy);

  @override
  String toString() => 'Place($text, ±$accuracy m)';
}

/// Why the device could not say where it is.
enum NoPlace {
  /// The user, or the device's privacy settings, did not let the app know.
  denied,

  /// Location is switched off for the whole device.
  off,

  /// Nothing on the device could tell in time: no GPS fix indoors, say,
  /// or no Wi-Fi to work it out from.
  unknown,
}

/// What asking the device where it is came to: a place, or why not.
@immutable
class Located {
  const Located.at(Place this.place) : why = null;
  const Located.not(NoPlace this.why) : place = null;

  final Place? place;
  final NoPlace? why;
}

/// The device's own way of knowing where it is, and of showing a place
/// on a map. Only ever used when the user asks.
abstract class Locator {
  /// Works out where the device is now. The first time, the device may
  /// ask the user whether the app may know.
  Future<Located> locate();

  /// Opens the device's settings where location can be switched on or
  /// allowed for the app.
  Future<void> openSettings();

  /// Shows [place] in the user's map app or, on a PC, on OpenStreetMap
  /// in the browser. False if there was nothing to show it in.
  Future<bool> openMap(Place place);

  /// Whether a map opens in the web browser, which then learns the place,
  /// rather than in a map app on the device.
  bool get mapsInBrowser;
}
