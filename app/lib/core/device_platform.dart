import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

import '../calls/call_audio.dart';
import '../calls/call_camera.dart';
import '../calls/pc_call_camera.dart';
import '../radio/channel_radio.dart';
import '../radio/direct_wifi.dart';
import '../radio/lan_radio.dart';
import '../radio/polled_radio.dart';
import '../radio/radio.dart';
import '../data/place.dart';
import 'core_bridge.dart';
import 'device_location.dart';
import 'device_notices.dart';
import 'device_voice.dart';
import 'voice.dart';

/// What only the operating system can give the app: where its private
/// folder is, the key that unlocks its data, and its radio.
abstract final class DevicePlatform {
  static const _channel = MethodChannel('dnet/platform');

  /// The folder the vault lives in. Private to the app on Android, private
  /// to the Windows account on a PC. Never a synced or shared folder.
  static Future<String> dataDir() async {
    if (Platform.isWindows) {
      // LOCALAPPDATA, not APPDATA: this must not roam to other machines.
      return '${Platform.environment['LOCALAPPDATA']}\\DNet';
    }
    return (await _channel.invokeMethod<String>('dataDir'))!;
  }

  /// The key that unlocks the vault, as 64 hex digits.
  ///
  /// On Android it is kept wrapped by a key in the Android Keystore, which
  /// never leaves the phone's secure hardware. On Windows this returns null
  /// and the core guards the key itself with the signed-in account.
  ///
  /// With [fresh], the old key is destroyed and a new one made. That is the
  /// last step of wiping everything.
  static Future<String?> masterKey({bool fresh = false}) async {
    if (Platform.isWindows) return null;
    return _channel.invokeMethod<String>('masterKey', {'fresh': fresh});
  }

  /// Tells the device whether pictures of the app's screen may be taken.
  /// When they may not, a screenshot or a screen recording shows the app's
  /// window as blank, and on Android it is hidden in the list of recent
  /// apps too.
  static void screenshots(bool allowed) {
    _channel
        .invokeMethod<void>('screenshots', {'allowed': allowed})
        .catchError((Object _) {});
  }

  /// Opens the device's own "share" sheet with [text]. False where there
  /// is none, as on a PC, and the caller copies the text instead.
  static Future<bool> share(String text) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('share', {'text': text}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Hands a web link the user chose to open to the device's own browser.
  /// Only http and https links are handed over, re-written by the app so
  /// nothing else rides along. False if it could not be opened. The app
  /// itself never fetches the link.
  ///
  /// Tests put their own in [opener], so nothing is really opened.
  static Future<bool> openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return false;
    }
    final clean = uri.toString();
    if (clean.contains(RegExp(r'[\s"<>^`{|}\\]'))) return false;
    return opener(clean);
  }

  static Future<bool> Function(String url) opener = _openWithSystem;

  static Future<bool> _openWithSystem(String url) async {
    // A test run never reaches a real browser.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    try {
      if (Platform.isWindows) {
        // The link alone is passed, with no shell to read it, to what
        // Windows opens web links with.
        final run = await Process.run('rundll32', [
          'url.dll,FileProtocolHandler',
          url,
        ]);
        return run.exitCode == 0;
      }
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<bool>('openLink', {'url': url}) ??
            false;
      }
    } on PlatformException {
      return false;
    } on ProcessException {
      return false;
    }
    return false;
  }

  /// Shows the device's own file chooser. Returns the path of the file the
  /// user chose, or null if they chose nothing. On Android the choice is
  /// copied into the app's own cache first, because Android hands apps a
  /// reference to a file, not a path.
  static Future<String?> pickFile() =>
      _channel.invokeMethod<String>('pickFile');

  /// Where files the user receives are saved, as ordinary files that other
  /// apps can open. Wiping everything removes what the app saved there.
  static Future<String> receivedDir() async {
    if (Platform.isWindows) {
      // A folder of the app's own. Plain "DNet" may be a folder the user
      // already has, and Storage would then count everything in it.
      return '${Platform.environment['USERPROFILE']}\\Downloads\\DNet Files';
    }
    return (await _channel.invokeMethod<String>('receivedDir'))!;
  }

  /// The microphone and speaker during a call. Null on a device the app
  /// has none for, and calls are then not offered.
  static CallAudio? callAudio() {
    if (Platform.isAndroid) return ChannelCallAudio();
    if (Platform.isWindows) {
      try {
        return LibraryCallAudio(_windowsLibrary().call);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// The camera during a video call. Null on a device the app has none
  /// for, and video calls are then not offered.
  static CallCamera? callCamera() {
    if (Platform.isAndroid) return ChannelCallCamera();
    if (Platform.isWindows) return PcCallCamera.open();
    return null;
  }

  /// The microphone and speaker, for voice messages. Null on a device the
  /// app has none for.
  static Voice? voice() {
    if (Platform.isAndroid) return ChannelVoice();
    if (Platform.isWindows) {
      try {
        return LibraryVoice(_windowsLibrary().call);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// The device's own way of knowing where it is, for a place the user
  /// chooses to send. Null on a device the app has none for.
  static Locator? locator() {
    if (Platform.isAndroid) return ChannelLocator();
    if (Platform.isWindows) {
      try {
        return LibraryLocator(_windowsLibrary().call);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// Wi-Fi Direct, for a fast link to a device that shares no network
  /// with this one. Null on a device the app has none for.
  static DirectWifi? directWifi() {
    if (Platform.isAndroid) return ChannelDirectWifi();
    if (Platform.isWindows) {
      try {
        return LibraryDirectWifi(_windowsLibrary().call);
      } on ArgumentError {
        return null;
      }
    }
    return null;
  }

  /// The Windows radio, microphone and speaker are one library, beside
  /// the program. It answers the same way the core does.
  static CoreBridge _windowsLibrary() => _library ??= CoreBridge(
    DynamicLibrary.open('dnet_radio.dll'),
    call: 'dnet_radio_call',
    free: 'dnet_radio_free',
  );
  static CoreBridge? _library;

  /// The device's own notifications, and whether the app goes on in the
  /// background once put away. Android and Windows; nothing elsewhere.
  static DeviceNotices notices() => Platform.isAndroid || Platform.isWindows
      ? ChannelNotices()
      : const NoNotices();

  /// The radio that finds people nearby: Bluetooth on both platforms. A
  /// device with none gets a radio that never finds anyone, and the Nearby
  /// screen says so.
  static Radio radio() {
    if (Platform.isAndroid) {
      // Android shows a notice while the radio runs with the app in the
      // background. Its words come from the same place as all the others.
      final l10n = lookupAppLocalizations(const Locale('en'));
      return MultiRadio(
        ChannelRadio(
          noticeTitle: l10n.linkNoticeTitle,
          noticeText: l10n.linkNoticeText,
        ),
        LanRadio(),
      );
    }
    if (Platform.isWindows) {
      try {
        return MultiRadio(PolledRadio(_windowsLibrary().call), LanRadio());
      } on ArgumentError {
        // No Bluetooth library. The local network link still works.
        return MultiRadio(NoRadio(), LanRadio());
      }
    }
    return NoRadio();
  }
}
