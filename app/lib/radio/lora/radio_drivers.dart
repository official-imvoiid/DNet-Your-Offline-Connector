import 'dart:io';

import 'byte_link.dart';
import 'meshtastic_driver.dart';
import 'mock_radio_driver.dart';
import 'radio_transport.dart';
import 'serial_lora_driver.dart';
import 'windows_serial.dart';

/// Which driver speaks to a device, and how it is reached.
enum RadioDriverChoice { meshtastic, serialLora }

/// Makes the transport for a device the user chose. Each platform reaches
/// a device differently:
///
/// | Platform | USB serial | Bluetooth LE | TCP (Wi-Fi) |
/// |---|---|---|---|
/// | Android | USB host API (`RadioSerial.kt`), needs an OTG cable | `RadioBle.kt` | yes |
/// | Windows | the COM port, through the Windows API | not in this release | yes |
/// | Linux, macOS | the tty as a file | not in this release | yes |
/// | iOS | no (Apple allows no serial) | would be the only way | yes |
///
/// iOS is not a build target of this repository; the table says what it
/// would be. See docs/RADIO.md.
abstract final class RadioDrivers {
  /// The transport for [endpoint] with [driver]. Throws [RadioException]
  /// for a pairing this platform cannot do, so the screen can say so
  /// before anything is tried.
  static RadioTransport make(
    RadioEndpoint endpoint, {
    RadioDriverChoice driver = RadioDriverChoice.meshtastic,
    MockAir? air,
  }) {
    switch (endpoint.kind) {
      case RadioEndpointKind.mock:
        return MockRadioDriver(air ?? MockAir(), node: 1);
      case RadioEndpointKind.tcp:
        if (driver != RadioDriverChoice.meshtastic) {
          throw const RadioException(
            'a serial LoRa module has no network connection',
            permanent: true,
          );
        }
        return MeshtasticDriver(
          TcpByteLink(endpoint.address, port: endpoint.port),
        );
      case RadioEndpointKind.serial:
        final ByteLink link = Platform.isAndroid
            ? ChannelByteLink.serial(endpoint.address)
            : Platform.isWindows
            ? WindowsSerialLink(endpoint.address)
            : DeviceFileSerialLink(endpoint.address);
        return driver == RadioDriverChoice.meshtastic
            ? MeshtasticDriver(link)
            : SerialLoraDriver(link);
      case RadioEndpointKind.ble:
        if (!Platform.isAndroid) {
          throw const RadioException(
            'Bluetooth to a radio is only built for Android in this release. '
            'Use USB or Wi-Fi here.',
            permanent: true,
          );
        }
        if (driver != RadioDriverChoice.meshtastic) {
          throw const RadioException(
            'a serial LoRa module is reached over USB, not Bluetooth',
            permanent: true,
          );
        }
        return MeshtasticDriver(ChannelByteLink.ble(endpoint.address));
    }
  }

  /// Whether this platform can reach a device this way at all.
  static bool canUse(RadioEndpointKind kind) => switch (kind) {
    RadioEndpointKind.tcp => true,
    RadioEndpointKind.serial =>
      Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS,
    RadioEndpointKind.ble => Platform.isAndroid,
    RadioEndpointKind.mock => false,
  };

  /// The devices this platform can see right now, of each kind it can
  /// reach: serial ports, and on Android the Bluetooth devices that
  /// carry the Meshtastic service. TCP devices have to be typed in.
  static Future<List<RadioEndpoint>> discover() async {
    final found = <RadioEndpoint>[];
    if (Platform.isAndroid) {
      found.addAll(await ChannelByteLink.list('serial'));
      found.addAll(await ChannelByteLink.list('ble'));
    } else if (Platform.isWindows) {
      // USB ports first; a Bluetooth serial port is listed last, since it
      // is almost never a radio.
      final ports = WindowsSerialLink.list()
        ..sort(
          (a, b) => (a.kind == SerialPortKind.bluetooth ? 1 : 0).compareTo(
            b.kind == SerialPortKind.bluetooth ? 1 : 0,
          ),
        );
      for (final port in ports) {
        found.add(RadioEndpoint.serial(port.port, serialKind: port.kind));
      }
    } else if (canUse(RadioEndpointKind.serial)) {
      for (final port in await DeviceFileSerialLink.list()) {
        found.add(RadioEndpoint.serial(port));
      }
    }
    return found;
  }
}
