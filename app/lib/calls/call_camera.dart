import 'package:flutter/services.dart';

/// The camera during a video call. Each kind of device has its own; a
/// device with none the app can use has none, and video calls are not
/// offered there.
///
/// It hands over small JPEG pictures, a few a second, each small enough
/// for one frame on a fast link. Sealing and sending them are the call
/// engine's work.
abstract class CallCamera {
  /// The largest picture worth handing over. A frame on the local network
  /// holds 16 KB and the sealing takes a little of that.
  static const maxBytes = 15 * 1024;

  /// Starts the camera. [picture] is given each picture it takes, and how
  /// many quarter turns clockwise it needs to stand upright. False if it
  /// cannot be used, which is nearly always because the user has not
  /// allowed it.
  Future<bool> start(void Function(Uint8List jpeg, int quarterTurns) picture);

  Future<void> stop();
}

/// The camera on Android, reached through the app's Kotlin side
/// (`CallCamera.kt`), which hands over each picture as it is taken.
///
/// Not yet verified on devices.
class ChannelCallCamera extends CallCamera {
  ChannelCallCamera() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'picture' && call.arguments is Map) {
        final picture = call.arguments as Map;
        final jpeg = picture['jpeg'];
        final turns = picture['turns'];
        if (jpeg is Uint8List && turns is int) _picture?.call(jpeg, turns);
      }
    });
  }

  // Must match the channel name in MainActivity.kt.
  static const _channel = MethodChannel('dnet/camera');
  void Function(Uint8List jpeg, int quarterTurns)? _picture;

  @override
  Future<bool> start(
    void Function(Uint8List jpeg, int quarterTurns) picture,
  ) async {
    _picture = picture;
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _picture = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing was running.
    } on MissingPluginException {
      // Nothing was running.
    }
  }
}
