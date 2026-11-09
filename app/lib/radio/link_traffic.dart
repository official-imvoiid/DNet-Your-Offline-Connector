/// A file smaller than this is a small file: its pieces go before those
/// of bigger files, though always after chat. The same line as
/// `SMALL_FILE` in core/src/file.rs, which is what sorts them.
const smallFileBytes = 1024 * 1024;

/// What is waiting to go out on one radio, by how much it matters.
class LinkWaiting {
  const LinkWaiting({
    this.messages = 0,
    this.smallBytes = 0,
    this.bigBytes = 0,
  });

  /// Chat messages, receipts and call control not yet handed over.
  final int messages;

  /// Pieces of small files, in bytes.
  final int smallBytes;

  /// Pieces of big files, in bytes.
  final int bigBytes;

  bool get isEmpty => messages == 0 && smallBytes == 0 && bigBytes == 0;

  @override
  bool operator ==(Object other) =>
      other is LinkWaiting &&
      other.messages == messages &&
      other.smallBytes == smallBytes &&
      other.bigBytes == bigBytes;

  @override
  int get hashCode => Object.hash(messages, smallBytes, bigBytes);
}

/// The links as they are this moment: how many people each radio reaches,
/// and what is waiting on it.
///
/// Someone reached by both Bluetooth and Wi-Fi is counted on both, since
/// both carry for them: chat goes on each, and files on Wi-Fi.
class LinkTraffic {
  const LinkTraffic({
    this.bluetoothPeople = 0,
    this.wifiPeople = 0,
    this.radioPeople = 0,
    this.bluetooth = const LinkWaiting(),
    this.wifi = const LinkWaiting(),
    this.radio = const LinkWaiting(),
  });

  final int bluetoothPeople;
  final int wifiPeople;

  /// People reached over a LoRa radio.
  final int radioPeople;
  final LinkWaiting bluetooth;
  final LinkWaiting wifi;
  final LinkWaiting radio;

  @override
  bool operator ==(Object other) =>
      other is LinkTraffic &&
      other.bluetoothPeople == bluetoothPeople &&
      other.wifiPeople == wifiPeople &&
      other.radioPeople == radioPeople &&
      other.bluetooth == bluetooth &&
      other.wifi == wifi &&
      other.radio == radio;

  @override
  int get hashCode => Object.hash(
    bluetoothPeople,
    wifiPeople,
    radioPeople,
    bluetooth,
    wifi,
    radio,
  );
}
