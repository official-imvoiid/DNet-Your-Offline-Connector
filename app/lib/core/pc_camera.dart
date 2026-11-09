import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'core_bridge.dart';

typedef _FrameNative = Uint64 Function(Pointer<Uint8>, IntPtr, Pointer<Uint32>);
typedef _FrameDart = int Function(Pointer<Uint8>, int, Pointer<Uint32>);

/// One picture from the camera: BGRA pixels, row after row.
class CameraFrame {
  const CameraFrame(this.seq, this.width, this.height, this.pixels);

  /// Goes up with each picture.
  final int seq;
  final int width;
  final int height;
  final Uint8List pixels;
}

/// The PC's camera, through the Windows radio library. It is on only while
/// the user is reading a code, and its pictures are held in memory only:
/// none is ever saved.
///
/// Not yet verified on devices.
class PcCamera {
  PcCamera._(this._call, this._frame);

  static const _library = 'dnet_radio.dll';

  /// The camera, or null where there is no radio library to reach it.
  static PcCamera? open() {
    if (!Platform.isWindows) return null;
    try {
      final library = DynamicLibrary.open(_library);
      return PcCamera._(
        CoreBridge(
          library,
          call: 'dnet_radio_call',
          free: 'dnet_radio_free',
        ).call,
        library.lookupFunction<_FrameNative, _FrameDart>('dnet_radio_frame'),
      );
    } on ArgumentError {
      return null;
    }
  }

  /// How many cameras the PC has. Asked away from the screen's thread, as
  /// Windows may take a moment to look; none if it takes too long.
  static Future<int> count() async {
    if (!Platform.isWindows) return 0;
    try {
      return await Isolate.run(() {
        final library = DynamicLibrary.open(_library);
        final reply = CoreBridge(
          library,
          call: 'dnet_radio_call',
          free: 'dnet_radio_free',
        ).call({'op': 'camera_count'});
        return reply is int ? reply : 0;
      }).timeout(const Duration(seconds: 3), onTimeout: () => 0);
    } on Object {
      return 0;
    }
  }

  final Object? Function(Map<String, Object?> request) _call;
  final _FrameDart _frame;

  Pointer<Uint8> _buffer = nullptr;
  int _capacity = 0;
  final Pointer<Uint32> _size = malloc<Uint32>(2);

  Object? _ask(Map<String, Object?> request) {
    try {
      return _call(request);
    } on Exception {
      return null;
    }
  }

  void start() => _ask({'op': 'camera_start'});

  /// "starting", "on", "off", or why it is not on: "denied", "none" or
  /// "failed".
  String get state => switch (_ask({'op': 'camera_state'})) {
    {'state': final String state} => state,
    _ => 'failed',
  };

  /// Turns the camera off. Its last picture goes with it.
  void stop() {
    _ask({'op': 'camera_stop'});
    if (_buffer != nullptr) {
      // The last picture is not left lying in memory either.
      _buffer.asTypedList(_capacity).fillRange(0, _capacity, 0);
      malloc.free(_buffer);
      _buffer = nullptr;
      _capacity = 0;
    }
  }

  /// The newest picture, if there is one newer than [after].
  CameraFrame? frame({int after = 0}) {
    var seq = _frame(_buffer, _capacity, _size);
    final (width, height) = (_size[0], _size[1]);
    final needed = width * height * 4;
    if (seq == 0 && needed > _capacity) {
      // Room for a picture of this size, then ask again.
      if (_buffer != nullptr) malloc.free(_buffer);
      _buffer = malloc<Uint8>(needed);
      _capacity = needed;
      seq = _frame(_buffer, _capacity, _size);
    }
    if (seq == 0 || seq <= after) return null;
    return CameraFrame(
      seq,
      _size[0],
      _size[1],
      Uint8List.fromList(_buffer.asTypedList(_size[0] * _size[1] * 4)),
    );
  }
}
