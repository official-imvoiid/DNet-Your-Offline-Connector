import 'dart:collection';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/core_bridge.dart';
import 'call_audio.dart';

/// Something the user can share: a whole screen, or on a PC one window.
@immutable
class ScreenSource {
  const ScreenSource({
    required this.id,
    required this.window,
    this.name = '',
    this.primary = false,
  });

  /// What the capture knows it by.
  final String id;

  /// One window rather than a whole screen.
  final bool window;

  /// A window's title. Screens have none.
  final String name;

  /// The main screen, where there are several.
  final bool primary;

  static ScreenSource? fromMap(Object? map) {
    if (map is! Map) return null;
    final id = map['id'];
    if (id is! String) return null;
    return ScreenSource(
      id: id,
      window: map['kind'] == 'window',
      name: map['name'] is String ? map['name'] as String : '',
      primary: map['primary'] == true,
    );
  }
}

/// What the notice Android shows while the screen is shared says, in the
/// app's own words. A PC shows a coloured border of its own instead.
typedef ScreenNotice = ({String title, String text, String stop});

/// One piece of a shared screen: a JPEG square that goes at [x], [y] on a
/// picture [width] by [height]. [gen] changes whenever the picture does
/// (a new size, or a new sharing), so pieces of an old one are never put
/// on a new one.
///
/// In a frame it goes as one byte for the version, then [gen], [width],
/// [height], [x], [y], [w] and [h], two bytes each, high byte first, then
/// the JPEG.
@immutable
class ScreenPiece {
  const ScreenPiece({
    required this.gen,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.jpeg,
  });

  final int gen;
  final int width;
  final int height;
  final int x;
  final int y;
  final int w;
  final int h;
  final Uint8List jpeg;

  static const _version = 1;
  static const headerBytes = 15;

  /// The largest picture a screen may be, either way.
  static const most = 8192;

  (int, int, int, int) get rect => (x, y, w, h);

  Uint8List toFrame() {
    final out = Uint8List(headerBytes + jpeg.length);
    final view = ByteData.sublistView(out)..setUint8(0, _version);
    var at = 1;
    for (final n in [gen, width, height, x, y, w, h]) {
      view.setUint16(at, n);
      at += 2;
    }
    out.setRange(headerBytes, out.length, jpeg);
    return out;
  }

  /// Null for anything that is not a sound piece of a screen.
  static ScreenPiece? fromFrame(Uint8List data) {
    if (data.length <= headerBytes || data[0] != _version) return null;
    final view = ByteData.sublistView(data);
    int at(int i) => view.getUint16(1 + i * 2);
    final piece = ScreenPiece(
      gen: at(0),
      width: at(1),
      height: at(2),
      x: at(3),
      y: at(4),
      w: at(5),
      h: at(6),
      jpeg: Uint8List.sublistView(data, headerBytes),
    );
    final fits =
        piece.width > 0 &&
        piece.height > 0 &&
        piece.width <= most &&
        piece.height <= most &&
        piece.w > 0 &&
        piece.h > 0 &&
        piece.x + piece.w <= piece.width &&
        piece.y + piece.h <= piece.height;
    return fits ? piece : null;
  }

  static ScreenPiece? fromMap(Object? map, Uint8List? Function(Object?) jpeg) {
    if (map is! Map) return null;
    final bytes = jpeg(map['jpeg']);
    int? n(String key) => map[key] is int ? map[key] as int : null;
    final values = [
      for (final key in ['gen', 'width', 'height', 'x', 'y', 'w', 'h']) n(key),
    ];
    if (bytes == null || values.contains(null)) return null;
    return ScreenPiece(
      gen: values[0]! & 0xffff,
      width: values[1]!,
      height: values[2]!,
      x: values[3]!,
      y: values[4]!,
      w: values[5]!,
      h: values[6]!,
      jpeg: bytes,
    );
  }
}

/// How sharing is going, as the capture last said.
enum ScreenState {
  off,
  starting,
  on,

  /// Stopped from outside the app: the window shared was closed, or the
  /// user stopped it from Android's notice.
  ended,
  failed,
}

/// How fast a shared screen may go, and how wide.
///
/// A screen goes only over Wi-Fi, and the same link carries the call's
/// sound, which must not wait behind it. So a fixed share of the link is
/// used, split between everyone watching, since each gets their own copy.
/// The picture is kept wide enough to read before anything else: with
/// less to go round, pieces that changed simply arrive a little later.
@immutable
class ScreenRate {
  const ScreenRate(this.bytes, this.width);

  /// Bytes a second for everyone watching together. About 3 Mbit/s: well
  /// within what a Wi-Fi link between two devices carries, with room left
  /// for the sound.
  static const total = 400 * 1024;

  /// Bytes a second each watcher is sent.
  final int bytes;

  /// The widest picture sent, in pixels.
  final int width;

  factory ScreenRate.forWatchers(int watchers) {
    final each = total ~/ (watchers < 1 ? 1 : watchers);
    final width = each >= 250 * 1024
        ? 1920
        : each >= 120 * 1024
        ? 1600
        : 1280;
    return ScreenRate(each, width);
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenRate && other.bytes == bytes && other.width == width;

  @override
  int get hashCode => Object.hash(bytes, width);
}

/// Captures the user's screen during a call. Each kind of device has its
/// own; a device with none the app can use has none, and sharing is not
/// offered there.
///
/// Nothing is captured until [start] is given what the user picked. It
/// hands over squares of the screen that changed, each a JPEG small
/// enough for one frame, no faster than [rate] allows. Sealing and
/// sending them are the call engine's work.
abstract class ScreenCapture {
  /// Android asks the user what to share itself, so the app shows no list
  /// of its own there.
  bool get systemPicks => false;

  /// What can be shared right now.
  Future<List<ScreenSource>> sources();

  /// Starts sharing [source]. False if it cannot be, which on Android is
  /// nearly always because the user said no.
  Future<bool> start(
    ScreenSource source, {
    required ScreenRate rate,
    required ScreenNotice notice,
  });

  void rate(ScreenRate rate);

  /// Sends the whole picture again, for someone who just started watching.
  void refresh();

  /// The pieces ready to send, and how sharing is going.
  Future<({ScreenState state, List<ScreenPiece> pieces})> take();

  Future<void> stop();

  /// The capture this device has, or null.
  static ScreenCapture? forDevice() {
    if (Platform.isAndroid) return ChannelScreenCapture();
    if (Platform.isWindows) return PcScreenCapture.open();
    return null;
  }
}

ScreenState _stateOf(Object? state) => switch (state) {
  'starting' => ScreenState.starting,
  'on' => ScreenState.on,
  'ended' => ScreenState.ended,
  'failed' => ScreenState.failed,
  _ => ScreenState.off,
};

/// The screen on a PC, through the radio library (`screen.rs`), which uses
/// Windows' own capture and draws a border round what is shared.
///
/// Not yet verified on devices.
class PcScreenCapture extends ScreenCapture {
  PcScreenCapture(this._call);

  /// The capture, or null where there is no radio library to reach it.
  static PcScreenCapture? open() {
    try {
      final library = DynamicLibrary.open('dnet_radio.dll');
      return PcScreenCapture(
        CoreBridge(
          library,
          call: 'dnet_radio_call',
          free: 'dnet_radio_free',
        ).call,
      );
    } on ArgumentError {
      return null;
    }
  }

  final Object? Function(Map<String, Object?> request) _call;

  Object? _ask(Map<String, Object?> request) {
    try {
      return _call(request);
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<ScreenSource>> sources() async => switch (_ask({
    'op': 'screen_sources',
  })) {
    final List<Object?> all => all.map(ScreenSource.fromMap).nonNulls.toList(),
    _ => const [],
  };

  @override
  Future<bool> start(
    ScreenSource source, {
    required ScreenRate rate,
    required ScreenNotice notice,
  }) async {
    this.rate(rate);
    if (_ask({'op': 'screen_start', 'source': source.id}) != true) {
      return false;
    }
    // Windows takes a moment to begin.
    for (var tries = 0; tries < 30; tries++) {
      final state = switch (_ask({'op': 'screen_state'})) {
        {'state': final Object? state} => _stateOf(state),
        _ => ScreenState.failed,
      };
      if (state == ScreenState.on) return true;
      if (state != ScreenState.starting) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await stop();
    return false;
  }

  @override
  void rate(ScreenRate rate) =>
      _ask({'op': 'screen_rate', 'bytes': rate.bytes, 'width': rate.width});

  @override
  void refresh() => _ask({'op': 'screen_refresh'});

  @override
  Future<({ScreenState state, List<ScreenPiece> pieces})> take() async {
    final taken = _ask({'op': 'screen_take'});
    if (taken is! Map) {
      return (state: ScreenState.failed, pieces: const <ScreenPiece>[]);
    }
    final pieces = [
      for (final piece in (taken['pieces'] as List? ?? const []))
        ?ScreenPiece.fromMap(
          piece,
          (hex) => hex is String ? bytesOf(hex) : null,
        ),
    ];
    return (state: _stateOf(taken['state']), pieces: pieces);
  }

  @override
  Future<void> stop() async => _ask({'op': 'screen_stop'});
}

/// The screen on Android, through the app's Kotlin side (`ScreenShare.kt`),
/// which asks Android first and shows a notice while sharing.
///
/// Not yet verified on devices.
class ChannelScreenCapture extends ScreenCapture {
  // Must match the channel name in ScreenShare.kt.
  static const _channel = MethodChannel('dnet/screen');

  @override
  bool get systemPicks => true;

  @override
  Future<List<ScreenSource>> sources() async => const [
    ScreenSource(id: 'screen', window: false),
  ];

  @override
  Future<bool> start(
    ScreenSource source, {
    required ScreenRate rate,
    required ScreenNotice notice,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('start', {
            'title': notice.title,
            'text': notice.text,
            'stop': notice.stop,
            // A phone's screen is narrower than a PC's: its full width
            // goes, up to what the link allows.
            'width': rate.width,
            'bytes': rate.bytes,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void rate(ScreenRate rate) => _channel
      .invokeMethod<void>('rate', {'bytes': rate.bytes, 'width': rate.width})
      .catchError((Object _) {});

  @override
  void refresh() =>
      _channel.invokeMethod<void>('refresh').catchError((Object _) {});

  @override
  Future<({ScreenState state, List<ScreenPiece> pieces})> take() async {
    try {
      final taken = await _channel.invokeMethod<Map<Object?, Object?>>('take');
      final pieces = [
        for (final piece in (taken?['pieces'] as List? ?? const []))
          ?ScreenPiece.fromMap(piece, (b) => b is Uint8List ? b : null),
      ];
      return (state: _stateOf(taken?['state']), pieces: pieces);
    } on PlatformException {
      return (state: ScreenState.failed, pieces: const <ScreenPiece>[]);
    } on MissingPluginException {
      return (state: ScreenState.failed, pieces: const <ScreenPiece>[]);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing was running.
    } on MissingPluginException {
      // Nothing was running.
    }
  }
}

/// Someone else's screen as it has arrived so far. Pieces are kept in the
/// order they came, newest last, and one that covers older ones replaces
/// them. Kept in memory only, and dropped when they stop sharing.
class SharedScreen extends ChangeNotifier {
  SharedScreen(this.from);

  /// Who is sharing it.
  final String from;

  int gen = -1;
  int width = 0;
  int height = 0;
  final LinkedHashMap<(int, int, int, int), ScreenPiece> _pieces =
      LinkedHashMap();

  /// What to draw, oldest first.
  Iterable<ScreenPiece> get pieces => _pieces.values;

  bool get hasPicture => _pieces.isNotEmpty;

  /// Puts a piece on the picture. A piece of a new picture starts it
  /// afresh.
  void add(ScreenPiece piece) {
    if (piece.gen != gen || piece.width != width || piece.height != height) {
      gen = piece.gen;
      width = piece.width;
      height = piece.height;
      _pieces.clear();
    }
    _pieces.removeWhere(
      (_, old) =>
          old.x >= piece.x &&
          old.y >= piece.y &&
          old.x + old.w <= piece.x + piece.w &&
          old.y + old.h <= piece.y + piece.h,
    );
    _pieces[piece.rect] = piece;
    notifyListeners();
  }
}
