import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'byte_link.dart';
import 'radio_transport.dart';

/// A COM port on Windows, opened through the Windows API itself
/// (kernel32), not as a file.
///
/// Windows hands out a serial port to one handle at a time, so it is
/// opened once, for reading and writing. The port is set to 115200 baud,
/// 8 data bits, no parity, one stop bit, no flow control, with DTR and
/// RTS on together in one step, as the official Meshtastic clients leave
/// them: boards with a native USB port (nRF52, ESP32-S3) only talk once
/// DTR is on, and setting both at once does not reset an ESP32 behind a
/// USB bridge. Reads never block: the port is asked every [pollEvery]
/// what has arrived, and a port that has gone (the cable pulled) ends
/// the stream.
///
/// Not yet tried with a real device: checked on Windows only for how it
/// lists ports and how it fails on one that is not there.
class WindowsSerialLink extends ByteLink {
  WindowsSerialLink(
    this.port, {
    this.baud = 115200,
    this.pollEvery = const Duration(milliseconds: 20),
  });

  /// "COM3".
  final String port;
  final int baud;
  final Duration pollEvery;

  int? _handle;
  Timer? _poll;
  Pointer<Uint8>? _buffer;
  Pointer<Uint32>? _count;
  Pointer<Uint8>? _comStat;
  var _read = StreamController<Uint8List>.broadcast();

  static const _bufferSize = 4096;

  @override
  String get name => port;

  /// The serial ports Windows knows of now, from the registry key the
  /// serial drivers fill in, each with a word on what it is.
  static List<SerialPortInfo> list() {
    if (!Platform.isWindows) return const [];
    try {
      return _Win.instance.ports()
        ..sort((a, b) => a.number.compareTo(b.number));
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> open() async {
    if (_handle != null) return;
    if (!Platform.isWindows) {
      throw const RadioException(
        'a COM port exists only on Windows',
        permanent: true,
      );
    }
    if (!RegExp(r'^COM\d{1,3}$').hasMatch(port)) {
      throw RadioException('$port is not a COM port', permanent: true);
    }
    // Opened again after closing: the old stream is done, so a new one.
    if (_read.isClosed) _read = StreamController<Uint8List>.broadcast();
    final win = _Win.instance;
    final handle = win.open(port);
    if (handle == null) {
      final there = list().any((p) => p.port == port);
      throw RadioException(
        there
            ? 'could not open $port. Another app may have it open (the '
                  'Meshtastic web client, Arduino, a terminal): close it, or '
                  'unplug the radio and plug it back in'
            : 'there is no $port now. Plug the radio in, or pick another '
                  'port',
      );
    }
    final problem = win.configure(handle, baud);
    if (problem != null) {
      win.close(handle);
      throw RadioException('could not set up $port: $problem');
    }
    _handle = handle;
    _buffer = calloc<Uint8>(_bufferSize);
    _count = calloc<Uint32>();
    _comStat = calloc<Uint8>(12);
    _poll = Timer.periodic(pollEvery, (_) => _drain());
  }

  /// Reads what has arrived, if anything.
  void _drain() {
    final handle = _handle;
    if (handle == null) return;
    final waiting = _Win.instance.waiting(handle, _count!, _comStat!);
    if (waiting == null) {
      // The port is gone: unplugged, or the driver let go of it.
      unawaited(close());
      return;
    }
    var left = waiting;
    while (left > 0) {
      final want = left < _bufferSize ? left : _bufferSize;
      final got = _Win.instance.read(handle, _buffer!, want, _count!);
      if (got == null) {
        unawaited(close());
        return;
      }
      if (got == 0) break;
      _read.add(Uint8List.fromList(_buffer!.asTypedList(got)));
      left -= got;
    }
  }

  @override
  Future<void> close() async {
    final handle = _handle;
    _handle = null;
    _poll?.cancel();
    _poll = null;
    if (handle != null) {
      _Win.instance.close(handle);
      if (!_read.isClosed) await _read.close();
    }
    for (final p in [_buffer, _count, _comStat]) {
      if (p != null) calloc.free(p);
    }
    _buffer = null;
    _count = null;
    _comStat = null;
  }

  @override
  Future<void> write(List<int> bytes) async {
    final handle = _handle;
    if (handle == null) throw const RadioException('the port is closed');
    final data = calloc<Uint8>(bytes.length);
    final written = calloc<Uint32>();
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      var done = 0;
      // A write that times out returns having taken part of it; a few
      // goes, then the port is taken to be stuck.
      for (var tries = 0; done < bytes.length && tries < 4; tries++) {
        final ok = _Win.instance.write(
          handle,
          data + done,
          bytes.length - done,
          written,
        );
        if (!ok) {
          await close();
          throw RadioException('$port dropped');
        }
        done += written.value;
      }
      if (done < bytes.length) {
        throw RadioException('$port is not taking bytes');
      }
    } finally {
      calloc.free(data);
      calloc.free(written);
    }
  }

  @override
  Stream<Uint8List> get read => _read.stream;
}

/// A COM port as Windows lists it.
class SerialPortInfo {
  const SerialPortInfo(this.port, this.device);

  /// "COM3".
  final String port;

  /// The driver's name for it, such as `\Device\Silabser0`.
  final String device;

  int get number => int.tryParse(port.substring(3)) ?? 0;

  /// What sort of port it is, read from the driver's name.
  SerialPortKind get kind => kindOf(device);

  static SerialPortKind kindOf(String device) {
    final d = device.toLowerCase();
    if (d.contains('bthmodem') || d.contains('bthenum')) {
      return SerialPortKind.bluetooth;
    }
    if (d.contains('silabser')) return SerialPortKind.cp210x;
    if (d.contains('ch341') || d.contains('wch') || d.contains('ch9102')) {
      return SerialPortKind.ch34x;
    }
    if (d.contains('vcp') || d.contains('ftdi')) return SerialPortKind.ftdi;
    if (d.contains('usbser')) return SerialPortKind.usbNative;
    return SerialPortKind.other;
  }
}

typedef _CreateFileC = IntPtr Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  IntPtr,
);
typedef _CreateFileD = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  int,
);
typedef _HandleBufC = Int32 Function(IntPtr, Pointer<Uint8>);
typedef _HandleBufD = int Function(int, Pointer<Uint8>);
typedef _HandleC = Int32 Function(IntPtr);
typedef _HandleD = int Function(int);
typedef _SetupC = Int32 Function(IntPtr, Uint32, Uint32);
typedef _SetupD = int Function(int, int, int);
typedef _PurgeC = Int32 Function(IntPtr, Uint32);
typedef _PurgeD = int Function(int, int);
typedef _ClearErrC = Int32 Function(IntPtr, Pointer<Uint32>, Pointer<Uint8>);
typedef _ClearErrD = int Function(int, Pointer<Uint32>, Pointer<Uint8>);
typedef _IoC = Int32 Function(
  IntPtr,
  Pointer<Uint8>,
  Uint32,
  Pointer<Uint32>,
  IntPtr,
);
typedef _IoD = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, int);
typedef _RegOpenC = Int32 Function(
  IntPtr,
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<IntPtr>,
);
typedef _RegOpenD = int Function(
  int,
  Pointer<Utf16>,
  int,
  int,
  Pointer<IntPtr>,
);
typedef _RegEnumC = Int32 Function(
  IntPtr,
  Uint32,
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint8>,
  Pointer<Uint32>,
);
typedef _RegEnumD = int Function(
  int,
  int,
  Pointer<Utf16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint8>,
  Pointer<Uint32>,
);
typedef _RegCloseC = Int32 Function(IntPtr);
typedef _RegCloseD = int Function(int);

/// The handful of Windows calls a serial port needs.
class _Win {
  _Win._() {
    final k = DynamicLibrary.open('kernel32.dll');
    final a = DynamicLibrary.open('advapi32.dll');
    _createFile = k.lookupFunction<_CreateFileC, _CreateFileD>('CreateFileW');
    _getCommState = k.lookupFunction<_HandleBufC, _HandleBufD>('GetCommState');
    _setCommState = k.lookupFunction<_HandleBufC, _HandleBufD>('SetCommState');
    _setTimeouts = k.lookupFunction<_HandleBufC, _HandleBufD>(
      'SetCommTimeouts',
    );
    _setupComm = k.lookupFunction<_SetupC, _SetupD>('SetupComm');
    _purge = k.lookupFunction<_PurgeC, _PurgeD>('PurgeComm');
    _clearError = k.lookupFunction<_ClearErrC, _ClearErrD>('ClearCommError');
    _readFile = k.lookupFunction<_IoC, _IoD>('ReadFile');
    _writeFile = k.lookupFunction<_IoC, _IoD>('WriteFile');
    _closeHandle = k.lookupFunction<_HandleC, _HandleD>('CloseHandle');
    _regOpen = a.lookupFunction<_RegOpenC, _RegOpenD>('RegOpenKeyExW');
    _regEnum = a.lookupFunction<_RegEnumC, _RegEnumD>('RegEnumValueW');
    _regClose = a.lookupFunction<_RegCloseC, _RegCloseD>('RegCloseKey');
  }

  static final instance = _Win._();

  late final _CreateFileD _createFile;
  late final _HandleBufD _getCommState;
  late final _HandleBufD _setCommState;
  late final _HandleBufD _setTimeouts;
  late final _SetupD _setupComm;
  late final _PurgeD _purge;
  late final _ClearErrD _clearError;
  late final _IoD _readFile;
  late final _IoD _writeFile;
  late final _HandleD _closeHandle;
  late final _RegOpenD _regOpen;
  late final _RegEnumD _regEnum;
  late final _RegCloseD _regClose;

  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;
  static const _invalidHandle = -1;

  /// Opens `\\.\COMn` (the form that works for every number, COM10 and
  /// up included). Null if Windows refuses.
  int? open(String port) {
    final path = '\\\\.\\$port'.toNativeUtf16();
    try {
      final handle = _createFile(
        path,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      return handle == _invalidHandle || handle == 0 ? null : handle;
    } finally {
      calloc.free(path);
    }
  }

  /// 8N1 at [baud], no flow control, DTR and RTS on, reads that return
  /// at once with what there is, writes that give up after half a
  /// second. Null if it took; else what did not.
  String? configure(int handle, int baud) {
    final dcb = calloc<Uint8>(28);
    final timeouts = calloc<Uint32>(5);
    try {
      _setupComm(handle, 8192, 8192);
      dcb.cast<Uint32>().value = 28; // DCBlength
      if (_getCommState(handle, dcb) == 0) return 'the port did not answer';
      ByteData.sublistView(dcb.asTypedList(28))
        ..setUint32(4, baud, Endian.little)
        // fBinary, DTR_CONTROL_ENABLE (bits 4-5 = 1), RTS_CONTROL_ENABLE
        // (bits 12-13 = 1); no parity check, no CTS/DSR or XON/XOFF flow
        // control, no abort on error.
        ..setUint32(8, 0x1011, Endian.little)
        ..setUint8(18, 8) // ByteSize
        ..setUint8(19, 0) // NOPARITY
        ..setUint8(20, 0); // ONESTOPBIT
      if (_setCommState(handle, dcb) == 0) return 'the port refused 115200 8N1';
      // ReadIntervalTimeout MAXDWORD with no totals: a read returns at
      // once with whatever has arrived.
      timeouts[0] = 0xFFFFFFFF;
      timeouts[1] = 0;
      timeouts[2] = 0;
      timeouts[3] = 0;
      timeouts[4] = 500;
      if (_setTimeouts(handle, timeouts.cast<Uint8>()) == 0) {
        return 'the port refused its timeouts';
      }
      // PURGE_RXCLEAR | PURGE_TXCLEAR: nothing stale from before.
      _purge(handle, 0x0008 | 0x0004);
      return null;
    } finally {
      calloc.free(dcb);
      calloc.free(timeouts);
    }
  }

  /// How many bytes are waiting to be read. Null if the port is gone.
  int? waiting(int handle, Pointer<Uint32> errors, Pointer<Uint8> comStat) {
    if (_clearError(handle, errors, comStat) == 0) return null;
    // COMSTAT: a DWORD of flags, then cbInQue.
    return comStat.cast<Uint32>()[1];
  }

  /// Reads up to [want] bytes into [buffer]. Null if the port is gone.
  int? read(int handle, Pointer<Uint8> buffer, int want, Pointer<Uint32> got) {
    got.value = 0;
    if (_readFile(handle, buffer, want, got, 0) == 0) return null;
    return got.value;
  }

  bool write(
    int handle,
    Pointer<Uint8> data,
    int length,
    Pointer<Uint32> written,
  ) {
    written.value = 0;
    return _writeFile(handle, data, length, written, 0) != 0;
  }

  void close(int handle) => _closeHandle(handle);

  /// The ports in HKLM\HARDWARE\DEVICEMAP\SERIALCOMM: each value is a
  /// driver's device name, its data the COM port's name.
  List<SerialPortInfo> ports() {
    const hklm = -2147483646; // HKEY_LOCAL_MACHINE, sign-extended
    const keyRead = 0x20019;
    final subKey = r'HARDWARE\DEVICEMAP\SERIALCOMM'.toNativeUtf16();
    final key = calloc<IntPtr>();
    final name = calloc<Uint16>(256).cast<Utf16>();
    final nameLength = calloc<Uint32>();
    final type = calloc<Uint32>();
    final data = calloc<Uint8>(512);
    final dataLength = calloc<Uint32>();
    final found = <SerialPortInfo>[];
    try {
      if (_regOpen(hklm, subKey, 0, keyRead, key) != 0) return found;
      for (var i = 0; i < 256; i++) {
        nameLength.value = 256;
        dataLength.value = 512;
        final result = _regEnum(
          key.value,
          i,
          name,
          nameLength,
          nullptr,
          type,
          data,
          dataLength,
        );
        if (result != 0) break; // ERROR_NO_MORE_ITEMS, or anything else
        const regSz = 1;
        if (type.value != regSz) continue;
        final chars = dataLength.value ~/ 2;
        final port = String.fromCharCodes(
          data.cast<Uint16>().asTypedList(chars),
        ).replaceAll('\u0000', '').trim();
        if (!RegExp(r'^COM\d{1,3}$').hasMatch(port)) continue;
        found.add(
          SerialPortInfo(port, name.toDartString(length: nameLength.value)),
        );
      }
      _regClose(key.value);
      return found;
    } finally {
      calloc.free(subKey);
      calloc.free(key);
      calloc.free(name);
      calloc.free(nameLength);
      calloc.free(type);
      calloc.free(data);
      calloc.free(dataLength);
    }
  }
}
