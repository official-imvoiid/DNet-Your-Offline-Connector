import 'package:flutter/services.dart';

import 'voice.dart';

/// The microphone and speaker on Android, reached through the app's
/// Kotlin side.
///
/// Not yet verified on devices.
class ChannelVoice implements Voice {
  // Must match the channel name in MainActivity.kt.
  static const _channel = MethodChannel('dnet/voice');

  Future<bool> _ask(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> start(String path) => _ask('start', {'path': path});

  @override
  Future<bool> stop() => _ask('stop');

  @override
  Future<void> cancel() => _ask('cancel');

  @override
  Future<bool> play(String path) => _ask('play', {'path': path});

  @override
  Future<void> stopPlaying() => _ask('stopPlaying');
}

/// The microphone and speaker on Windows, reached through the same
/// library as the radio. It answers the way the core does.
///
/// Not yet verified on devices.
class LibraryVoice implements Voice {
  LibraryVoice(this._call);

  final Object? Function(Map<String, Object?> request) _call;

  bool _ask(Map<String, Object?> request) {
    try {
      return _call(request) == true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> start(String path) async =>
      _ask({'op': 'voice_start', 'path': path});

  @override
  Future<bool> stop() async => _ask({'op': 'voice_stop'});

  /// The app deletes the file. All that is needed here is to stop.
  @override
  Future<void> cancel() async => _ask({'op': 'voice_stop'});

  @override
  Future<bool> play(String path) async =>
      _ask({'op': 'voice_play', 'path': path});

  @override
  Future<void> stopPlaying() async => _ask({'op': 'voice_stop_playing'});
}
