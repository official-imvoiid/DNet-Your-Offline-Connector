import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'radio_transport.dart';

/// A plain stream of bytes to and from a device: a TCP socket to a
/// Meshtastic node on Wi-Fi, a USB serial port, or a Bluetooth LE
/// connection. The Meshtastic driver and the serial LoRa driver both
/// speak over one of these and do not care which.
abstract class ByteLink {
  /// Opens the link. Throws [RadioException] if it cannot.
  Future<void> open();

  /// Closes it. Safe to call twice.
  Future<void> close();

  /// Writes bytes. Throws [RadioException] once the link is gone.
  Future<void> write(List<int> bytes);

  /// Bytes as they arrive. Done when the link is gone.
  Stream<Uint8List> get read;

  /// What this link is, for the user: "192.168.1.20:4403", "COM3",
  /// "/dev/ttyUSB0", "Heltec_a1b2".
  String get name;

  /// Whether the link is a Bluetooth LE one, which frames differently.
  bool get isBle => false;
}

/// How a device is reached. The user picks one on the Radio screen.
class RadioEndpoint {
  const RadioEndpoint.tcp(this.address, {this.port = 4403})
    : kind = RadioEndpointKind.tcp,
      serialKind = null;
  const RadioEndpoint.serial(this.address, {this.serialKind})
    : kind = RadioEndpointKind.serial,
      port = 0;
  const RadioEndpoint.ble(this.address)
    : kind = RadioEndpointKind.ble,
      port = 0,
      serialKind = null;
  const RadioEndpoint.mock()
    : kind = RadioEndpointKind.mock,
      address = 'mock',
      port = 0,
      serialKind = null;

  final RadioEndpointKind kind;

  /// For a serial port found by looking, what is behind it, where the
  /// system says. Shown when choosing; not kept, and not part of what
  /// makes two endpoints the same.
  final SerialPortKind? serialKind;

  /// The host, the port's path or name, or the BLE address.
  final String address;
  final int port;

  String get label => switch (kind) {
    RadioEndpointKind.tcp => '$address:$port',
    RadioEndpointKind.serial || RadioEndpointKind.ble => address,
    RadioEndpointKind.mock => 'Mock radio',
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'address': address,
    'port': port,
  };

  static RadioEndpoint? fromJson(Object? json) {
    if (json case {
      'kind': final String kind,
      'address': final String address,
    }) {
      final port = json['port'] is int ? json['port'] as int : 4403;
      return switch (kind) {
        'tcp' => RadioEndpoint.tcp(address, port: port),
        'serial' => RadioEndpoint.serial(address),
        'ble' => RadioEndpoint.ble(address),
        'mock' => const RadioEndpoint.mock(),
        _ => null,
      };
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is RadioEndpoint &&
      other.kind == kind &&
      other.address == address &&
      other.port == port;

  @override
  int get hashCode => Object.hash(kind, address, port);
}

enum RadioEndpointKind { tcp, serial, ble, mock }

/// What is behind a COM port, as far as its driver's name tells.
enum SerialPortKind {
  /// The board's own USB (ESP32-S3, nRF52: Heltec V4, RAK, T-Echo,
  /// T1000-E), Windows' built-in driver.
  usbNative,

  /// A Silicon Labs CP210x USB bridge (Heltec V3, older T-Beams).
  cp210x,

  /// A WCH CH340 or CH9102 USB bridge (many LILYGO and budget boards).
  ch34x,

  /// An FTDI USB bridge.
  ftdi,

  /// A Bluetooth serial port: not a radio plugged in by USB.
  bluetooth,
  other,
}

/// A Meshtastic node on the same Wi-Fi, on its TCP port (4403 by
/// default). Works on every platform the app runs on. Only local
/// network addresses are connected to: the app has no business on the
/// internet, and a pasted address must not be able to send it there.
class TcpByteLink extends ByteLink {
  TcpByteLink(
    this.host, {
    this.port = 4403,
    this.timeout = const Duration(seconds: 6),
  });

  final String host;
  final int port;
  final Duration timeout;
  Socket? _socket;
  var _read = StreamController<Uint8List>.broadcast();

  @override
  String get name => '$host:$port';

  /// Whether an address is on a local network, as the local Wi-Fi link
  /// decides it: private ranges and this machine only.
  static bool isLocal(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final [a, b, ...] = address.rawAddress;
    return a == 10 ||
        a == 127 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254);
  }

  @override
  Future<void> open() async {
    if (_socket != null) return;
    // Opened again after closing: the old stream is done, so a new one.
    if (_read.isClosed) _read = StreamController<Uint8List>.broadcast();
    // A number, never a name: looking a name up would be a call to a
    // DNS server, and the app makes no network calls of its own.
    final address = InternetAddress.tryParse(host);
    if (address == null || !isLocal(address)) {
      throw RadioException(
        '$host is not an address on this local network',
        permanent: true,
      );
    }
    await _connect(address);
  }

  Future<void> _connect(InternetAddress address) async {
    final Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
    } on SocketException catch (e) {
      throw RadioException('could not reach $name: ${e.message}');
    } on OSError catch (e) {
      // A connection reset as it was made comes back as the bare error.
      throw RadioException('could not reach $name: ${e.message}');
    } on TimeoutException {
      throw RadioException('$name did not answer');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socket = socket;
    socket.listen(
      (data) => _read.add(data),
      onError: (Object _) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.destroy();
      if (!_read.isClosed) {
        // Tell the reader the link is gone, then take a fresh controller
        // so the link can be opened again.
        await _read.close();
      }
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) throw const RadioException('the link is closed');
    try {
      socket.add(bytes);
      await socket.flush();
    } on SocketException catch (e) {
      await close();
      throw RadioException('the link dropped: ${e.message}');
    } on StateError {
      await close();
      throw const RadioException('the link dropped');
    }
  }

  @override
  Stream<Uint8List> get read => _read.stream;
}

/// A USB serial port, opened as the operating system's device file:
/// /dev/ttyUSB0 or /dev/ttyACM0 on Linux, /dev/cu.usbserial-* on macOS.
/// The port's speed is set with `stty` first. Meshtastic and the serial
/// LoRa firmware both speak at 115200.
///
/// Not for Windows: a COM port there can be opened by one handle only
/// and blocks a read until its buffer fills, so it is reached through
/// `WindowsSerialLink` instead. On Android the port is reached through
/// [ChannelByteLink], since Android gives apps no device file.
///
/// Not yet tried with a real device: checked here with a pseudo-terminal.
class DeviceFileSerialLink extends ByteLink {
  DeviceFileSerialLink(this.path, {this.baud = 115200, this.configure = true});

  final String path;
  final int baud;

  /// Whether to set the speed with the system tool. Off for a pty in
  /// tests.
  final bool configure;
  RandomAccessFile? _writer;
  var _read = StreamController<Uint8List>.broadcast();

  @override
  String get name => path;

  /// The serial ports this PC has, by looking where each system keeps
  /// them. Empty where it cannot tell.
  static Future<List<String>> list() async {
    try {
      if (Platform.isWindows) {
        final run = await Process.run('cmd', ['/c', 'mode']);
        final out = run.stdout.toString();
        return {
          for (final m in RegExp(r'COM(\d+)').allMatches(out)) m.group(0)!,
        }.toList()..sort();
      }
      if (Platform.isLinux || Platform.isMacOS) {
        final found = <String>[];
        await for (final entry in Directory('/dev').list()) {
          final name = entry.path.split('/').last;
          if (name.startsWith('ttyUSB') ||
              name.startsWith('ttyACM') ||
              name.startsWith('cu.usbserial') ||
              name.startsWith('cu.usbmodem') ||
              name.startsWith('cu.SLAB')) {
            found.add(entry.path);
          }
        }
        return found..sort();
      }
    } on Object {
      // Nothing to list.
    }
    return const [];
  }

  @override
  Future<void> open() async {
    if (_writer != null) return;
    // Opened again after closing: the old stream is done, so a new one.
    if (_read.isClosed) _read = StreamController<Uint8List>.broadcast();
    // Opening for writing would make a plain file where there is no
    // port. Only a device that is there is opened.
    if (!await File(path).exists()) {
      throw RadioException('there is no port at $path');
    }
    if (configure) await _setSpeed();
    try {
      // Not append: a terminal cannot seek, and there is nothing to
      // truncate on one either.
      _writer = await File(path).open(mode: FileMode.writeOnly);
      _reader = await File(path).open(mode: FileMode.read);
    } on FileSystemException catch (e) {
      throw RadioException(
        'could not open $path: ${e.osError?.message ?? e.message}',
      );
    }
    unawaited(_readLoop(_reader!));
  }

  RandomAccessFile? _reader;

  /// Reads until the port is closed. A stream read of a terminal would
  /// stop at once, since a terminal has no length; reading it a piece at
  /// a time waits for bytes instead.
  Future<void> _readLoop(RandomAccessFile reader) async {
    try {
      while (identical(_reader, reader)) {
        final bytes = await reader.read(4096);
        if (!identical(_reader, reader)) break;
        if (bytes.isEmpty) {
          // The port is gone.
          await close();
          break;
        }
        _read.add(bytes);
      }
    } on FileSystemException {
      await close();
    }
  }

  Future<void> _setSpeed() async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', [
          '/c',
          'mode',
          '$path:',
          'BAUD=$baud',
          'PARITY=n',
          'DATA=8',
          'STOP=1',
        ]);
      } else {
        await Process.run('stty', [
          '-F',
          path,
          '$baud',
          'raw',
          '-echo',
          'cs8',
          '-cstopb',
          '-parenb',
        ]);
      }
    } on ProcessException {
      // Without the tool the port keeps its last speed, which is usually
      // right for a USB serial bridge.
    }
  }

  @override
  Future<void> close() async {
    final writer = _writer;
    _writer = null;
    final reader = _reader;
    _reader = null;
    try {
      await reader?.close();
    } on FileSystemException {
      // Already gone.
    }
    if (writer != null) {
      try {
        await writer.close();
      } on FileSystemException {
        // Already gone.
      }
      if (!_read.isClosed) await _read.close();
    }
  }

  @override
  Future<void> write(List<int> bytes) async {
    final writer = _writer;
    if (writer == null) throw const RadioException('the port is closed');
    try {
      // A RandomAccessFile write goes straight to the device; there is no
      // buffer to flush, and a terminal refuses a flush anyway.
      await writer.writeFrom(bytes);
    } on FileSystemException catch (e) {
      await close();
      throw RadioException('the port dropped: ${e.message}');
    }
  }

  @override
  Stream<Uint8List> get read => _read.stream;
}

/// A serial port or a Bluetooth LE device reached through the platform's
/// own code: Android's USB host API and BluetoothGatt, in
/// RadioSerial.kt and RadioBle.kt. The platform side owns the device and
/// streams bytes; this side only passes them on.
class ChannelByteLink extends ByteLink {
  ChannelByteLink.serial(String address) : _kind = 'serial', _address = address;
  ChannelByteLink.ble(String address) : _kind = 'ble', _address = address;

  // Both must match the names in MainActivity.kt.
  static const _methods = MethodChannel('dnet/radio_link');
  static const _events = EventChannel('dnet/radio_link/events');

  final String _kind;
  final String _address;
  StreamSubscription<Object?>? _listening;
  var _read = StreamController<Uint8List>.broadcast();
  bool _open = false;

  @override
  String get name => _address;

  @override
  bool get isBle => _kind == 'ble';

  /// The devices the platform can see of each kind: serial ports with
  /// permission already given or askable, and BLE devices that carry the
  /// Meshtastic service.
  static Future<List<RadioEndpoint>> list(String kind) async {
    try {
      final found = await _methods.invokeMethod<List<Object?>>('list', {
        'kind': kind,
      });
      return [
        for (final entry in found ?? const [])
          if (entry case {'address': final String address})
            kind == 'ble'
                ? RadioEndpoint.ble(address)
                : RadioEndpoint.serial(address),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> open() async {
    if (_open) return;
    // Opened again after closing: the old stream is done, so a new one.
    if (_read.isClosed) _read = StreamController<Uint8List>.broadcast();
    _listening ??= _events
        .receiveBroadcastStream({'kind': _kind, 'address': _address})
        .listen(
          (event) {
            if (event is Uint8List) _read.add(event);
          },
          onError: (Object _) => close(),
          onDone: close,
        );
    try {
      final ok = await _methods.invokeMethod<bool>('open', {
        'kind': _kind,
        'address': _address,
      });
      if (ok != true) throw RadioException('could not open $_address');
    } on PlatformException catch (e) {
      await _listening?.cancel();
      _listening = null;
      throw RadioException(
        e.message ?? 'could not open $_address',
        permanent: e.code == 'permanent',
      );
    } on MissingPluginException {
      await _listening?.cancel();
      _listening = null;
      throw const RadioException(
        'this device has no serial or Bluetooth link for radios',
        permanent: true,
      );
    }
    _open = true;
  }

  @override
  Future<void> close() async {
    if (!_open && _listening == null) return;
    _open = false;
    await _listening?.cancel();
    _listening = null;
    try {
      await _methods.invokeMethod<void>('close', {
        'kind': _kind,
        'address': _address,
      });
    } on PlatformException {
      // Already closed.
    } on MissingPluginException {
      // Nothing to close.
    }
    if (!_read.isClosed) await _read.close();
  }

  @override
  Future<void> write(List<int> bytes) async {
    if (!_open) throw const RadioException('the link is closed');
    try {
      await _methods.invokeMethod<void>('write', {
        'kind': _kind,
        'address': _address,
        'data': Uint8List.fromList(bytes),
      });
    } on PlatformException catch (e) {
      await close();
      throw RadioException(e.message ?? 'the link dropped');
    }
  }

  @override
  Stream<Uint8List> get read => _read.stream;
}
