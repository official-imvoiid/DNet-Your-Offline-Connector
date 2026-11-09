import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'byte_link.dart';
import 'radio_transport.dart';

/// What the user chose on the Radio screen: which device, over what, and
/// which band. Kept as a small JSON file in the app's private folder.
/// None of it is secret: an address and a region name. Whether the radio
/// is switched on at all is a link setting kept by the core with the
/// other switches ("links/long_range").
@immutable
class RadioSettings {
  const RadioSettings({this.endpoint, this.regionCode});

  /// How the device is reached, or null if none has been chosen.
  final RadioEndpoint? endpoint;

  /// The band the user picked, by [RadioRegion.code], or null if they
  /// have not picked one. The radio keeps whatever it was set to until
  /// they do, and the screen says so.
  final String? regionCode;

  RadioRegion? get region =>
      regionCode == null ? null : RadioRegion.byCode(regionCode!);

  bool get isSetUp => endpoint != null;

  RadioSettings copyWith({
    RadioEndpoint? endpoint,
    bool clearEndpoint = false,
    String? regionCode,
  }) => RadioSettings(
    endpoint: clearEndpoint ? null : endpoint ?? this.endpoint,
    regionCode: regionCode ?? this.regionCode,
  );

  Map<String, Object?> toJson() => {
    'endpoint': endpoint?.toJson(),
    'region': regionCode,
  };

  static RadioSettings fromJson(Object? json) {
    if (json is! Map) return const RadioSettings();
    return RadioSettings(
      endpoint: RadioEndpoint.fromJson(json['endpoint']),
      regionCode: switch (json['region']) {
        final String code when RadioRegion.byCode(code) != null => code,
        _ => null,
      },
    );
  }

  static const fileName = 'radio.json';

  /// Reads the settings from [dir]. Anything unreadable is no settings.
  /// The file is a few dozen bytes, so this is done at once.
  static RadioSettings load(String dir) {
    try {
      final text = File('$dir${Platform.pathSeparator}$fileName')
          .readAsStringSync();
      return fromJson(jsonDecode(text));
    } on FileSystemException {
      return const RadioSettings();
    } on FormatException {
      return const RadioSettings();
    }
  }

  /// Writes the settings to [dir], whole or not at all.
  void save(String dir) {
    final file = File('$dir${Platform.pathSeparator}$fileName');
    final temporary = File('${file.path}.new');
    temporary.parent.createSync(recursive: true);
    temporary.writeAsStringSync(jsonEncode(toJson()), flush: true);
    temporary.renameSync(file.path);
  }

  @override
  bool operator ==(Object other) =>
      other is RadioSettings &&
      other.endpoint == endpoint &&
      other.regionCode == regionCode;

  @override
  int get hashCode => Object.hash(endpoint, regionCode);
}
