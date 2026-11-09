import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a notification is about. Calls ring louder than the rest.
enum NoticeKind { message, request, mention, call }

/// One notification, as the device shows it while DNet is not in front.
@immutable
class Notice {
  const Notice({
    required this.key,
    required this.kind,
    required this.title,
    required this.text,
  });

  /// What it is about: `chat:<person>`, `request:<person>`,
  /// `mention:<channel>` or `call`. A notice with the same key replaces the
  /// one before, and the key comes back when the user taps it.
  final String key;
  final NoticeKind kind;
  final String title;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Notice &&
      other.key == key &&
      other.kind == kind &&
      other.title == title &&
      other.text == text;

  @override
  int get hashCode => Object.hash(key, kind, title, text);

  @override
  String toString() => 'Notice($key, $kind, "$title", "$text")';
}

/// The words the device needs for its side of things, in the user's
/// language: the names of the kinds of notification, and on a PC the tray
/// icon's menu and the note shown the first time the window goes there.
@immutable
class NoticeWords {
  const NoticeWords({
    required this.messages,
    required this.calls,
    required this.appName,
    required this.open,
    required this.quit,
    required this.stillRunningTitle,
    required this.stillRunningText,
  });

  final String messages;
  final String calls;
  final String appName;
  final String open;
  final String quit;
  final String stillRunningTitle;
  final String stillRunningText;

  Map<String, String> toMap() => {
    'messages': messages,
    'calls': calls,
    'app': appName,
    'open': open,
    'quit': quit,
    'running_title': stillRunningTitle,
    'running_text': stillRunningText,
  };
}

/// The device's own notifications, and whether the app goes on in the
/// background once it is put away.
abstract class DeviceNotices {
  /// Whether the device lets the app show notifications at all.
  Future<bool> allowed();

  /// Asks the user to let the app show notifications, where the device
  /// asks. True if it may.
  Future<bool> ask();

  void show(Notice notice);
  void cancel(String key);
  void cancelAll();

  /// Whether the app goes on once put away: a phone keeps it running with
  /// a notice, a PC keeps it in the tray when the window is closed.
  void keepRunning(bool on);

  /// The words for the device's side; given once, at the start.
  void words(NoticeWords words);

  /// The key of each notice the user taps while the app is running.
  Stream<String> get opened;

  /// The key of the notice the app was started from, if it was.
  Future<String?> launchKey();
}

/// The device's notifications through the app's own channel. Android and
/// Windows both answer it; on anything else every call does nothing.
class ChannelNotices implements DeviceNotices {
  ChannelNotices() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened' && call.arguments is String) {
        _opened.add(call.arguments as String);
      }
      return null;
    });
  }

  // Must match the channel in MainActivity.kt and flutter_window.cpp.
  static const _channel = MethodChannel('dnet/notices');

  final _opened = StreamController<String>.broadcast();

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> allowed() async => await _call<bool>('allowed') ?? false;

  @override
  Future<bool> ask() async => await _call<bool>('ask') ?? false;

  @override
  void show(Notice notice) => _call<void>('show', {
    'key': notice.key,
    'kind': notice.kind.name,
    'title': notice.title,
    'text': notice.text,
  });

  @override
  void cancel(String key) => _call<void>('cancel', {'key': key});

  @override
  void cancelAll() => _call<void>('cancelAll');

  @override
  void keepRunning(bool on) => _call<void>('keepRunning', {'on': on});

  @override
  void words(NoticeWords words) => _call<void>('words', words.toMap());

  @override
  Stream<String> get opened => _opened.stream;

  @override
  Future<String?> launchKey() => _call<String>('launchKey');
}

/// A device with no notifications: every call does nothing.
class NoNotices implements DeviceNotices {
  const NoNotices();

  @override
  Future<bool> allowed() async => false;
  @override
  Future<bool> ask() async => false;
  @override
  void show(Notice notice) {}
  @override
  void cancel(String key) {}
  @override
  void cancelAll() {}
  @override
  void keepRunning(bool on) {}
  @override
  void words(NoticeWords words) {}
  @override
  Stream<String> get opened => const Stream.empty();
  @override
  Future<String?> launchKey() async => null;
}
