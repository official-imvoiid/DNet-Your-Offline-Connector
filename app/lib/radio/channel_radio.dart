import 'dart:async';

import 'package:flutter/services.dart';

import 'radio.dart';

/// Reads one event as the platform side reports it. Anything it does not
/// recognise is null, and ignored.
RadioEvent? radioEventFrom(Object? event) => switch (event) {
  {'t': 'up', 'link': final int link, 'max': final int max} => LinkUp(
    link,
    max,
  ),
  {'t': 'frame', 'link': final int link, 'data': final Uint8List data} =>
    FrameIn(link, hexEncode(data)),
  {'t': 'frame', 'link': final int link, 'frame': final String frame} =>
    FrameIn(link, frame),
  {'t': 'down', 'link': final int link} => LinkDown(link),
  {'t': 'sent', 'link': final int link, 'n': final int count} => FramesSent(
    link,
    count,
  ),
  {'t': 'signal', 'link': final int link, 'rssi': final int rssi} => SignalSeen(
    link,
    rssi,
  ),
  {'t': 'state', 'state': final String name} => switch (RadioState.values
      .where((s) => s.name == name)
      .firstOrNull) {
    final state? => RadioChanged(state),
    null => null,
  },
  _ => null,
};

const _digits = '0123456789abcdef';

String hexEncode(Uint8List bytes) {
  final out = StringBuffer();
  for (final byte in bytes) {
    out
      ..write(_digits[byte >> 4])
      ..write(_digits[byte & 15]);
  }
  return out.toString();
}

Uint8List hexDecode(String hex) => Uint8List.fromList([
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Bluetooth on Android. The radio itself is Kotlin, in
/// android/app/src/main/kotlin/org/dnet/dnet/BleRadio.kt; this passes
/// messages to and from it.
///
/// Not yet verified on devices.
class ChannelRadio extends Radio {
  ChannelRadio({this.noticeTitle = '', this.noticeText = ''});

  /// What Android's notice says while the radio runs in the background.
  final String noticeTitle;
  final String noticeText;

  // Both must match the names in MainActivity.kt.
  static const _methods = MethodChannel('dnet/radio');
  static const _events = EventChannel('dnet/radio/events');

  StreamSubscription<Object?>? _listening;

  @override
  Future<void> start() async {
    // Listen before starting, so nothing the radio says is missed.
    _listening ??= _events.receiveBroadcastStream().listen((event) {
      final read = radioEventFrom(event);
      if (read != null) onEvent?.call(read);
    });
    await _methods.invokeMethod<void>('start', {
      'notice_title': noticeTitle,
      'notice_text': noticeText,
    });
  }

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  void send(int link, List<String> frames) {
    _methods.invokeMethod<void>('send', {
      'link': link,
      'frames': [for (final frame in frames) hexDecode(frame)],
    });
  }

  @override
  void drop(int link) {
    _methods.invokeMethod<void>('drop', {'link': link});
  }

  @override
  Future<bool> askPermission() async =>
      await _methods.invokeMethod<bool>('ask') ?? false;
}
