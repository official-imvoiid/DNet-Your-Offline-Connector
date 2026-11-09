import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// An error the Rust core reported. [code] is stable and safe to switch on;
/// [message] is for logs, not for showing to the user.
class CoreException implements Exception {
  const CoreException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CoreException($code): $message';
}

typedef _CallNative = Pointer<Uint8> Function(
  Pointer<Uint8>,
  IntPtr,
  Pointer<IntPtr>,
);
typedef _CallDart = Pointer<Uint8> Function(
  Pointer<Uint8>,
  int,
  Pointer<IntPtr>,
);
typedef _FreeNative = Void Function(Pointer<Uint8>, IntPtr);
typedef _FreeDart = void Function(Pointer<Uint8>, int);

/// The app's only way into the Rust core: one JSON request in, one JSON
/// reply out. Identity, encryption and storage all live on the other side.
class CoreBridge {
  /// [call] and [free] name the two functions in [library]. The core's
  /// are the defaults. The Windows radio library answers in the same way
  /// under its own names.
  CoreBridge(
    DynamicLibrary library, {
    String call = 'dnet_call',
    String free = 'dnet_free',
  }) : _call = library.lookupFunction<_CallNative, _CallDart>(call),
       _free = library.lookupFunction<_FreeNative, _FreeDart>(free),
       _core = null;

  CoreBridge._(this._call, this._free, this._core);

  /// The same library, speaking to a separate core with its own identity
  /// and storage. The app has one core and never needs this. Tests that
  /// play several people give each of them one.
  CoreBridge onCore(int number) => CoreBridge._(_call, _free, number);

  /// Loads the core. With no [path], looks where each platform's build puts
  /// it: beside the program on Windows, inside the package on Android.
  factory CoreBridge.open([String? path]) => CoreBridge(
    DynamicLibrary.open(
      path ?? (Platform.isWindows ? 'dnet_core.dll' : 'libdnet_core.so'),
    ),
  );

  final _CallDart _call;
  final _FreeDart _free;
  final int? _core;

  /// Sends [request] and returns what the core answered. Throws a
  /// [CoreException] if the core refused.
  Object? call(Map<String, Object?> request) {
    final bytes = utf8.encode(jsonEncode({...request, 'core': ?_core}));
    final input = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final length = malloc<IntPtr>();
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final output = _call(input, bytes.length, length);
      final String text;
      try {
        text = utf8.decode(output.asTypedList(length.value));
      } finally {
        // The core allocated the reply, so the core frees it.
        _free(output, length.value);
      }
      final reply = jsonDecode(text) as Map<String, Object?>;
      if (reply['err'] case final Map<String, Object?> error) {
        throw CoreException(
          error['code'] as String? ?? 'unknown',
          error['message'] as String? ?? '',
        );
      }
      return reply['ok'];
    } finally {
      // The request can hold the master key. Clear it before letting go.
      input.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      malloc
        ..free(input)
        ..free(length);
    }
  }
}
