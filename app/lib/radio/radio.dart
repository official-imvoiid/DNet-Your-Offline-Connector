/// A way frames reach another device. Every link belongs to one, and
/// which is told by the link's number: see [LinkNumbers].
enum Transport {
  /// Bluetooth LE: finds people, carries chat, slow for files.
  bluetooth,

  /// The same Wi-Fi network, or a Wi-Fi Direct group: fast.
  wifi,

  /// An external LoRa radio: very long range, very slow, chat only.
  radio;

  /// The name the interface text selects on.
  String get wire => name;
}

/// Where each transport's link numbers start. A radio gives out numbers
/// from its own range, so a link can be told for one by its number alone
/// and the ranges never clash.
abstract final class LinkNumbers {
  /// Bluetooth links are numbered from 1.
  static const bluetooth = 0;

  /// The local network. Far above any Bluetooth gives out.
  static const network = 1 << 20;

  /// A LoRa radio. Above the network's.
  static const radio = 1 << 21;

  static Transport of(int link) => link >= radio
      ? Transport.radio
      : link >= network
      ? Transport.wifi
      : Transport.bluetooth;
}

/// What a radio tells the app.
sealed class RadioEvent {
  const RadioEvent();
}

/// A connection to another device is up. Nothing is known yet about who is
/// at the other end; the core works that out.
class LinkUp extends RadioEvent {
  const LinkUp(this.link, this.maxFrame);

  /// The radio's own number for this connection.
  final int link;

  /// The most bytes one frame can carry on it.
  final int maxFrame;
}

/// One frame arrived, as hex.
class FrameIn extends RadioEvent {
  const FrameIn(this.link, this.frame);
  final int link;
  final String frame;
}

/// How strongly the radio hears the device at the other end of a
/// connection, in dBm: -40 is very loud, -90 faint. A rough guide to how
/// near it is, which jumps about. It says nothing about which way.
class SignalSeen extends RadioEvent {
  const SignalSeen(this.link, this.rssi);
  final int link;
  final int rssi;
}

/// The radio has put [count] more frames of a connection on the air, and
/// has room for more. A radio that says so lets the app hold back what is
/// less urgent until there is room, so that a chat never waits behind a
/// file already handed over. One that never says so is given everything
/// at once, in order of what matters most.
class FramesSent extends RadioEvent {
  const FramesSent(this.link, this.count);
  final int link;
  final int count;
}

/// The connection is gone.
class LinkDown extends RadioEvent {
  const LinkDown(this.link);
  final int link;
}

/// Why the radio is or is not working.
enum RadioState {
  /// Not asked to run.
  off,

  /// Looking for people and letting itself be found.
  on,

  /// Bluetooth is switched off on the device.
  bluetoothOff,

  /// The user has not let the app use Bluetooth.
  noPermission,

  /// The device only lets apps look for Bluetooth devices while Location
  /// is switched on. Android 10 and 11 work this way.
  locationOff,

  /// This device cannot do it.
  unsupported,
}

class RadioChanged extends RadioEvent {
  const RadioChanged(this.state);
  final RadioState state;
}

/// A way of reaching devices nearby: Bluetooth today.
///
/// A radio only moves frames. It does not know who anyone is, cannot read
/// what it carries, and decides nothing. Splitting messages into frames,
/// proving who is at the other end and all encryption happen in the core.
abstract class Radio {
  /// Called for everything the radio has to report.
  void Function(RadioEvent event)? onEvent;

  /// Starts looking for devices and letting them find this one. Trouble is
  /// reported as a [RadioChanged], not thrown.
  Future<void> start();

  /// Stops, and drops every connection.
  Future<void> stop();

  /// Sends frames, each as hex, in order on one connection.
  void send(int link, List<String> frames);

  /// Ends one connection, and leaves that device alone for a while.
  void drop(int link);

  /// Asks the user for whatever the radio needs, where the platform has
  /// such a question. Returns true if the radio may now run.
  Future<bool> askPermission() async => true;

  /// Tells the radio that a DNet device is at this address on a local
  /// network, for a radio that can use one. The others take no notice.
  void reach(String address) {}
}

/// A radio for a device that has none the app can use. It never finds
/// anyone.
class NoRadio extends Radio {
  @override
  Future<void> start() async =>
      onEvent?.call(const RadioChanged(RadioState.unsupported));

  @override
  Future<void> stop() async {}

  @override
  void send(int link, List<String> frames) {}

  @override
  void drop(int link) {}
}
