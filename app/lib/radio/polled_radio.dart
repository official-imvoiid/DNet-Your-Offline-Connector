import 'dart:async';

import 'channel_radio.dart';
import 'radio.dart';

/// Bluetooth on Windows. The radio itself is Rust, in radio_windows/; it
/// cannot call into the app, so the app asks it what has happened several
/// times a second.
///
/// Not yet verified on devices.
class PolledRadio extends Radio {
  PolledRadio(this._call);

  /// One request to the radio library, answered at once.
  final Object? Function(Map<String, Object?> request) _call;

  static const _every = Duration(milliseconds: 50);
  Timer? _timer;

  @override
  Future<void> start() async {
    _call({'op': 'start'});
    _timer ??= Timer.periodic(_every, (_) => _poll());
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _call({'op': 'stop'});
  }

  void _poll() {
    final events = _call({'op': 'poll'});
    if (events is! List) return;
    for (final event in events) {
      final read = radioEventFrom(event);
      if (read != null) onEvent?.call(read);
    }
  }

  @override
  void send(int link, List<String> frames) {
    _call({'op': 'send', 'link': link, 'frames': frames});
  }

  @override
  void drop(int link) {
    _call({'op': 'drop', 'link': link});
  }

  @override
  Future<bool> askPermission() async {
    // Windows has no question to ask. This opens its Bluetooth settings,
    // where the user can switch Bluetooth on themselves.
    _call({'op': 'open_settings'});
    return false;
  }
}
