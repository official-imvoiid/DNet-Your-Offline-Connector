import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Tapping two phones together to swap chat links over NFC, reached
/// through the app's Kotlin side. A phone without NFC, and every PC, has
/// none, and the option is not shown there.
///
/// Not yet verified on devices.
abstract final class NfcTap {
  // Must match the channel name in MainActivity.kt.
  static const _channel = MethodChannel('dnet/nfc');

  static Future<bool>? _available;
  static final _reads = StreamController<String>.broadcast();
  static final _given = StreamController<void>.broadcast();
  static var _listening = false;

  /// Whether this device can tap at all. Asked once.
  static Future<bool> get available => _available ??= Platform.isAndroid
      ? _ask('available')
      : Future.value(false);

  /// Whether NFC is switched on now.
  static Future<bool> get enabled => _ask('enabled');

  /// Links read off phones tapped against this one.
  static Stream<String> get reads {
    _listen();
    return _reads.stream;
  }

  /// A phone tapped against this one has read the link offered.
  static Stream<void> get given {
    _listen();
    return _given.stream;
  }

  /// Offers [link] to a phone that taps this one, and reads theirs, until
  /// [stop].
  static Future<bool> start(String link) => _ask('start', {'link': link});

  static Future<void> stop() => _ask('stop');

  /// Opens the device's NFC settings, for switching it on.
  static Future<void> openSettings() => _ask('settings');

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'read':
          if (call.arguments case final String link) _reads.add(link);
        case 'given':
          _given.add(null);
      }
      return null;
    });
  }

  static Future<bool> _ask(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
