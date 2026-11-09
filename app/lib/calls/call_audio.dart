import 'dart:async';

import 'package:flutter/services.dart';

/// How sound moves during a call: 16-bit samples, little-endian, one
/// channel, 16,000 a second, in blocks of a fiftieth of a second.
abstract final class CallSound {
  static const rate = 16000;
  static const blockSamples = rate ~/ 50;
  static const blockBytes = blockSamples * 2;
  static const block = Duration(milliseconds: 20);
}

/// The microphone and the speaker during a call. Each kind of device has
/// its own; a device with neither has none, and calls are not offered
/// there.
///
/// It only listens and plays. Squeezing, sealing and sending the sound
/// are the core's work and the call engine's.
abstract class CallAudio {
  /// Starts the microphone and the speaker. [heard] is given each block
  /// the microphone takes in. Says which of the two could be started: the
  /// microphone fails where the user has not allowed it.
  Future<({bool mic, bool speaker})> start(
    void Function(Uint8List block) heard,
  );

  /// Queues one block for the speaker.
  void play(Uint8List block);

  /// Sends the sound to the loudspeaker rather than the earpiece, on a
  /// phone. A PC has only the one.
  void loudspeaker(bool on) {}

  /// Whether this device has an earpiece as well as a loudspeaker.
  bool get hasEarpiece => false;

  Future<void> stop();
}

/// The microphone and speaker on Windows, in the same library as the
/// radio. Windows cannot call into the app, so what the microphone heard
/// is collected, and what to play handed over, in one request a block.
///
/// Not yet verified on devices.
class LibraryCallAudio extends CallAudio {
  LibraryCallAudio(this._call);

  final Object? Function(Map<String, Object?> request) _call;
  Timer? _trading;
  final List<String> _toPlay = [];
  void Function(Uint8List block)? _heard;

  @override
  Future<({bool mic, bool speaker})> start(
    void Function(Uint8List block) heard,
  ) async {
    await stop();
    final Object? started;
    try {
      started = _call({'op': 'call_audio_start'});
    } on Exception {
      return (mic: false, speaker: false);
    }
    final (mic, speaker) = switch (started) {
      {'mic': final bool mic, 'speaker': final bool speaker} => (mic, speaker),
      _ => (false, false),
    };
    if (!mic && !speaker) return (mic: false, speaker: false);
    _heard = heard;
    _trading = Timer.periodic(CallSound.block, (_) => _trade());
    return (mic: mic, speaker: speaker);
  }

  void _trade() {
    final Object? got;
    try {
      got = _call({'op': 'call_audio', 'play': List.of(_toPlay)});
    } on Exception {
      return;
    } finally {
      _toPlay.clear();
    }
    if (got is! List) return;
    for (final block in got) {
      if (block is String) _heard?.call(_bytes(block));
    }
  }

  @override
  void play(Uint8List block) {
    _toPlay.add(_hex(block));
    // Never more than a quarter of a second waiting here: the library
    // keeps no more than that either.
    if (_toPlay.length > 12) _toPlay.removeAt(0);
  }

  @override
  Future<void> stop() async {
    _trading?.cancel();
    _trading = null;
    _heard = null;
    _toPlay.clear();
    try {
      _call({'op': 'call_audio_stop'});
    } on Exception {
      // Nothing was running.
    }
  }
}

/// The microphone and speaker on Android, reached through the app's
/// Kotlin side (`CallAudio.kt`). It hands over each block as it comes.
///
/// Not yet verified on devices.
class ChannelCallAudio extends CallAudio {
  ChannelCallAudio() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'heard' && call.arguments is Uint8List) {
        _heard?.call(call.arguments as Uint8List);
      }
    });
  }

  // Must match the channel name in MainActivity.kt.
  static const _channel = MethodChannel('dnet/call');
  void Function(Uint8List block)? _heard;

  @override
  bool get hasEarpiece => true;

  @override
  Future<({bool mic, bool speaker})> start(
    void Function(Uint8List block) heard,
  ) async {
    _heard = heard;
    try {
      final started = await _channel.invokeMethod<Map<Object?, Object?>>(
        'start',
      );
      return (
        mic: started?['mic'] == true,
        speaker: started?['speaker'] == true,
      );
    } on PlatformException {
      return (mic: false, speaker: false);
    } on MissingPluginException {
      return (mic: false, speaker: false);
    }
  }

  @override
  void play(Uint8List block) {
    _channel.invokeMethod<void>('play', block).catchError((Object _) {});
  }

  @override
  void loudspeaker(bool on) {
    _channel
        .invokeMethod<void>('loudspeaker', {'on': on})
        .catchError((Object _) {});
  }

  @override
  Future<void> stop() async {
    _heard = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing was running.
    } on MissingPluginException {
      // Nothing was running.
    }
  }
}

String _hex(Uint8List bytes) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (final byte in bytes) {
    out
      ..write(digits[byte >> 4])
      ..write(digits[byte & 15]);
  }
  return out.toString();
}

Uint8List _bytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Hex for the core, which takes and gives bytes that way.
String hexOf(Uint8List bytes) => _hex(bytes);

/// Bytes back from the core's hex.
Uint8List bytesOf(String hex) => _bytes(hex);
