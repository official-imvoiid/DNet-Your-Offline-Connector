import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'lora/lora_radio.dart';
import 'radio.dart';

/// Reaches DNet devices on the same local network: the same Wi-Fi, or one
/// device's hotspot with the other joined to it. No internet is used and
/// nothing leaves the local network.
///
/// It is many times faster than Bluetooth, so the core uses it for a
/// person whenever both links reach them.
///
/// Like every radio, it only moves frames. It does not know who anyone is
/// and cannot read what it carries: proving who is at the other end and
/// all encryption happen in the core, exactly as over Bluetooth. What it
/// says out loud on the network is "a DNet device is here", a number made
/// up afresh each time the app starts, and a port. Nothing about the user.
///
/// It does not make a network. Where two devices share none, Wi-Fi Direct
/// (`direct_wifi.dart`) makes one between them, and then tells this radio
/// the other's address with [greet].
///
/// Checked between two copies on one PC. Not yet verified on devices.
class LanRadio extends Radio {
  LanRadio({
    this.discoveryPort = 47474,
    this.announceEvery = const Duration(seconds: 3),
    this.pingEvery = const Duration(seconds: 2),
    this.quietFor = const Duration(seconds: 8),
    this.helloWait = const Duration(seconds: 10),
    this._announceTo,
  });

  /// How long a connection gets to say which running copy it is. One that
  /// says nothing is closed then: connections waiting for that count
  /// towards the most there may be, so a few that never spoke would
  /// otherwise keep every place taken.
  final Duration helloWait;

  /// How often each end of a link says "still here" to the other, and how
  /// long one may go unheard before the link is dropped. A network made
  /// by Wi-Fi Direct can vanish without a word, and a file must not sit
  /// waiting on it while Bluetooth is still there to carry on with.
  final Duration pingEvery;
  final Duration quietFor;

  /// Link numbers start here, far above any Bluetooth gives out, so the
  /// two never clash and a link can be told for a fast one by its number.
  static const firstLink = 1 << 20;

  /// The most one frame carries. A network connection takes far more than
  /// Bluetooth does.
  static const maxFrame = 16384;

  static const _hello = 'DNET1';

  /// The port every device listens on to hear who else is there.
  final int discoveryPort;
  final Duration announceEvery;

  /// Where "I am here" is sent. Everyone on the local network, unless a
  /// test says otherwise.
  final List<(InternetAddress, int)>? _announceTo;

  /// Made up afresh on every start. It only tells one running copy of the
  /// app from another. It is not who the user is.
  late String _id;

  ServerSocket? _server;
  RawDatagramSocket? _beacon;
  Timer? _announcing;
  Timer? _pinging;

  /// When each link was last heard from, by this clock.
  final Stopwatch _time = Stopwatch()..start();
  final Map<int, int> _lastHeard = {};
  int _nextLink = firstLink;

  final Map<int, Socket> _sockets = {};
  final Map<String, int> _linkOf = {};

  /// What is waiting to be written to each connection. Writes go one batch
  /// at a time, each handed to the network before the next, so the radio
  /// can say when frames have gone: see [FramesSent].
  final Map<Socket, _Out> _out = {};
  final Set<String> _connecting = {};

  /// Connections that have not yet said which copy they are, by where
  /// they came from.
  final Map<Socket, String> _pendingHello = {};

  /// Addresses this radio was told of one by one, and how many more
  /// times each is to be told "I am here".
  final Map<String, (InternetAddress, int, int)> _greeting = {};
  static const _greetings = 10;

  /// The most addresses greeted at once, and the most connections being
  /// made at once. Anyone on the network can say "I am here" from any
  /// address with any number, so without a limit one device could have
  /// this one greet and connect to the whole network for it.
  static const _mostGreeted = 32;
  static const _mostConnecting = 8;

  /// The most connections kept up. Beyond this, a new one is turned away
  /// at once: a device that opens connections and never proves who it
  /// is would otherwise hold a link, and the core's memory, for each.
  static const _mostLinks = 64;

  /// Whether an address is on a local network: the ranges kept for home
  /// and office networks and hotspots, and this device itself. The link
  /// neither answers nor connects to anything else, so it cannot be made
  /// to reach out to the internet by someone sending it a packet from
  /// there.
  static bool isLocal(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final [a, b, ...] = address.rawAddress;
    return a == 10 ||
        a == 127 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254);
  }

  /// The port this device takes connections on, once started.
  int? get port => _server?.port;

  /// Says "I am here" straight to one address, now and for a little while
  /// after. On a network made by Wi-Fi Direct, saying it to everyone does
  /// not always get through, but each end can be told where the other is.
  ///
  /// False, and nothing is sent, for an address that is not on a local
  /// network.
  bool greet(InternetAddress address, {int? port}) {
    if (!isLocal(address)) return false;
    final to = port ?? discoveryPort;
    final key = '${address.address} $to';
    final fresh = !_greeting.containsKey(key);
    if (fresh && _greeting.length >= _mostGreeted) return false;
    _greeting[key] = (address, to, _greetings);
    if (fresh) _say([(address, to)]);
    return true;
  }

  @override
  void reach(String address) {
    final parsed = InternetAddress.tryParse(address);
    if (parsed != null) greet(parsed);
    // A network has just been made or joined. Look at once, not at the
    // next turn.
    _lookAround();
  }

  /// The address that means "everyone" on the network [address] is on, or
  /// null if that is not a local network.
  ///
  /// Saying "I am here" to the one address that means every network only
  /// goes out on a device's main network on some systems, and a Wi-Fi
  /// Direct group is never that. So it is also said on each network by
  /// name. This takes every network to be the usual size, 254 devices,
  /// which the ones phones and PCs make for Wi-Fi Direct are. On a bigger
  /// one it reaches a single address that is most likely nobody's.
  static InternetAddress? everyoneOn(InternetAddress address) {
    if (!isLocal(address) || address.isLoopback) return null;
    final [a, b, c, ...] = address.rawAddress;
    return InternetAddress('$a.$b.$c.255');
  }

  /// "Everyone" on each network this device is on right now.
  List<InternetAddress> _everyone = const [];
  int _beats = 0;

  Future<void> _lookAround() async {
    if (_announceTo != null) return;
    try {
      final found = <String, InternetAddress>{};
      for (final network in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final address in network.addresses) {
          final everyone = everyoneOn(address);
          if (everyone != null) found[everyone.address] = everyone;
        }
      }
      _everyone = found.values.toList();
    } on SocketException {
      // The device would not say. What was known before still stands.
    }
  }

  @override
  Future<void> start() async {
    if (_server != null) return;
    final random = Random.secure();
    _id = [
      for (var i = 0; i < 8; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      server.listen(
        (socket) => _adopt(socket, initiated: false),
        onError: (Object _) {},
      );
      final beacon = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      beacon.broadcastEnabled = true;
      _beacon = beacon;
      beacon.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = beacon.receive();
        if (datagram != null) _heard(datagram);
      }, onError: (Object _) {});
    } on SocketException {
      await stop();
      onEvent?.call(const RadioChanged(RadioState.unsupported));
      return;
    }
    onEvent?.call(const RadioChanged(RadioState.on));
    _announce();
    _announcing = Timer.periodic(announceEvery, (_) => _announce());
    _pinging = Timer.periodic(pingEvery, (_) => _ping());
  }

  /// Says "still here" on every link, and drops any that has gone quiet.
  /// An empty frame is that word. It stays between the two radios: the
  /// app is never handed one.
  void _ping() {
    final now = _time.elapsedMilliseconds;
    for (final MapEntry(key: link, value: socket)
        in _sockets.entries.toList()) {
      if (now - (_lastHeard[link] ?? now) > quietFor.inMilliseconds) {
        _end(link);
      } else {
        _write(socket, const []);
      }
    }
  }

  @override
  Future<void> stop() async {
    _announcing?.cancel();
    _announcing = null;
    _pinging?.cancel();
    _pinging = null;
    _saying?.cancel();
    _saying = null;
    _unsaid.clear();
    _refused = 0;
    _beacon?.close();
    _beacon = null;
    await _server?.close();
    _server = null;
    for (final link in _sockets.keys.toList()) {
      _end(link);
    }
    for (final socket in _pendingHello.keys.toList()) {
      _out.remove(socket);
      socket.destroy();
    }
    _pendingHello.clear();
    _connecting.clear();
    _greeting.clear();
    _everyone = const [];
    _beats = 0;
  }

  void _announce() {
    // Networks come and go: a Wi-Fi Direct group, a hotspot, a cable.
    if (_beats++ % 5 == 0) _lookAround();
    _say([
      ...?_announceTo,
      if (_announceTo == null) ...[
        (InternetAddress('255.255.255.255'), discoveryPort),
        for (final everyone in _everyone) (everyone, discoveryPort),
      ],
      for (final (address, port, _) in _greeting.values) (address, port),
    ]);
    _greeting.updateAll((_, told) => (told.$1, told.$2, told.$3 - 1));
    _greeting.removeWhere((_, told) => told.$3 <= 0);
  }

  /// Places "I am here" is still to be said to. A datagram socket on
  /// Windows takes one send at a time: one made while the last is still
  /// going out sends nothing and returns 0. So a beat to several places,
  /// the whole network first, then each network by name, then anyone
  /// greeted, is said to one place after another, not all at once.
  final List<(InternetAddress, int)> _unsaid = [];
  List<int> _words = const [];
  Timer? _saying;
  int _refused = 0;

  void _say(List<(InternetAddress, int)> targets) {
    final beacon = _beacon;
    final server = _server;
    if (beacon == null || server == null) return;
    _words = utf8.encode('$_hello $_id ${server.port}');
    for (final target in targets) {
      // A place still waiting from the beat before is said to once.
      final waiting = _unsaid.any(
        (t) => t.$1.address == target.$1.address && t.$2 == target.$2,
      );
      if (!waiting) _unsaid.add(target);
    }
    _sayNext();
  }

  void _sayNext() {
    final beacon = _beacon;
    if (beacon == null) {
      _unsaid.clear();
      return;
    }
    while (_unsaid.isNotEmpty) {
      final (address, port) = _unsaid.first;
      try {
        if (beacon.send(_words, address, port) == 0) {
          // The last one is still going out. Tried again in a moment, but
          // not for ever: what is left waits for the next beat.
          if (++_refused > 50) {
            _unsaid.clear();
            _refused = 0;
            return;
          }
          _saying ??= Timer(const Duration(milliseconds: 2), () {
            _saying = null;
            _sayNext();
          });
          return;
        }
      } on SocketException {
        // No network to say it on just now. Tried again at the next beat.
      }
      _refused = 0;
      _unsaid.removeAt(0);
    }
  }

  /// Another device said it is here. One of the two connects: whichever
  /// has the lower number at once, the other a little later in case the
  /// first could not get through.
  void _heard(Datagram datagram) {
    final String words;
    try {
      words = utf8.decode(datagram.data);
    } on FormatException {
      return;
    }
    if (!isLocal(datagram.address)) return;
    final parts = words.split(' ');
    if (parts.length != 3 || parts[0] != _hello) return;
    final theirId = parts[1];
    final theirPort = int.tryParse(parts[2]);
    if (theirPort == null || theirPort <= 0 || theirPort > 65535) return;
    if (theirId == _id || theirId.length != 16) return;
    if (_linkOf.containsKey(theirId)) return;
    // They may not have heard this device: say so straight back, so that
    // whichever of the two is to connect knows where to.
    greet(datagram.address, port: datagram.port);
    // One connection on the way per address: a flood of made-up numbers
    // from one place gets one attempt, not one each. And only so many
    // at once from anywhere.
    final where = datagram.address.address;
    if (_connecting.contains(where) || _connecting.length >= _mostConnecting) {
      return;
    }
    _connecting.add(where);

    final wait = _id.compareTo(theirId) < 0
        ? Duration.zero
        : const Duration(milliseconds: 1500);
    Timer(wait, () async {
      try {
        if (_server == null || _linkOf.containsKey(theirId)) return;
        // The one that waited: if a connection from there is already in
        // and about to say who it is, that is most likely them. Not
        // connecting as well avoids two connections between one pair.
        // Should it turn out to be someone else, their next beacon is
        // another chance.
        if (wait > Duration.zero && _pendingHello.containsValue(where)) {
          return;
        }
        final socket = await Socket.connect(
          datagram.address,
          theirPort,
          timeout: const Duration(seconds: 4),
        );
        _adopt(socket, initiated: true);
      } on SocketException {
        // Not reachable that way. They may reach this device instead.
      } on OSError {
        // The same, said differently: a connection the other end reset
        // as it was made (its copy stopping, say) comes back from
        // Socket.connect as the bare system error.
      } finally {
        _connecting.remove(where);
      }
    });
  }

  /// Takes on a connection, whichever side made it. Each end first says
  /// which running copy it is, so that two connections between the same
  /// pair are not both kept. [initiated] is whether this radio made it.
  void _adopt(Socket socket, {required bool initiated}) {
    if (_server == null ||
        !isLocal(socket.remoteAddress) ||
        _sockets.length + _out.length >= _mostLinks) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final from = socket.remoteAddress.address;
    _pendingHello[socket] = from;
    _write(socket, utf8.encode('$_hello $_id'));

    int? link;
    final waiting = BytesBuilder(copy: false);
    Timer? helloBy;
    void close() {
      helloBy?.cancel();
      _pendingHello.remove(socket);
      if (link != null) {
        _end(link!);
      } else {
        _out.remove(socket);
        socket.destroy();
      }
    }

    helloBy = Timer(helloWait, () {
      if (link == null) close();
    });
    socket.listen(
      (data) {
        waiting.add(data);
        if (link != null) _lastHeard[link!] = _time.elapsedMilliseconds;
        var bytes = waiting.takeBytes();
        var at = 0;
        while (bytes.length - at >= 4) {
          final length = ByteData.sublistView(bytes, at, at + 4).getUint32(0);
          if (length == 0 && link != null) {
            // "Still here." Noted above, and nothing more to it.
            at += 4;
            continue;
          }
          // Nothing honest is bigger than a frame, and the first thing
          // said is never nothing.
          if (length == 0 || length > maxFrame) return close();
          if (bytes.length - at - 4 < length) break;
          final frame = Uint8List.sublistView(bytes, at + 4, at + 4 + length);
          at += 4 + length;
          if (link == null) {
            final theirId = _helloFrom(frame);
            if (theirId == null) return close();
            final existing = _linkOf[theirId];
            if (existing != null) {
              // Two connections between one pair, one made each way,
              // when both connected at once. Each end alone would keep
              // whichever spoke first, and that can differ between the
              // ends, each then closing the one the other kept. So both
              // keep the one the lower number made, and only when it
              // comes from where the link already is: a hello from
              // anywhere else with a known number is just closed.
              final held = _sockets[existing];
              final keep =
                  initiated == (_id.compareTo(theirId) < 0) &&
                  held != null &&
                  held.remoteAddress.address == from;
              if (!keep) return close();
              _end(existing);
            }
            _pendingHello.remove(socket);
            helloBy?.cancel();
            link = _nextLink++;
            _sockets[link!] = socket;
            _linkOf[theirId] = link!;
            _lastHeard[link!] = _time.elapsedMilliseconds;
            onEvent?.call(LinkUp(link!, maxFrame));
          } else {
            onEvent?.call(FrameIn(link!, _hex(frame)));
          }
        }
        if (at < bytes.length) waiting.add(Uint8List.sublistView(bytes, at));
      },
      onError: (Object _) => close(),
      onDone: close,
      cancelOnError: true,
    );
  }

  String? _helloFrom(Uint8List frame) {
    final String words;
    try {
      words = utf8.decode(frame);
    } on FormatException {
      return null;
    }
    final parts = words.split(' ');
    if (parts.length != 2 || parts[0] != _hello) return null;
    return parts[1] == _id || parts[1].length != 16 ? null : parts[1];
  }

  /// Writes one frame. [link] is set for a frame the app sent, which is
  /// counted when it has gone.
  void _write(Socket socket, List<int> frame, {int? link}) {
    final out = _out.putIfAbsent(socket, _Out.new);
    final length = ByteData(4)..setUint32(0, frame.length);
    out.waiting
      ..add(length.buffer.asUint8List())
      ..add(frame);
    if (link != null) {
      out.link = link;
      out.frames++;
    }
    _flush(socket, out);
  }

  void _flush(Socket socket, _Out out) {
    if (out.busy || out.waiting.isEmpty) return;
    final batch = BytesBuilder(copy: false);
    for (final bytes in out.waiting) {
      batch.add(bytes);
    }
    out.waiting.clear();
    final frames = out.frames;
    out.frames = 0;
    try {
      socket.add(batch.takeBytes());
    } on StateError {
      // Closed underneath. Its listener tidies up.
      return;
    }
    out.busy = true;
    socket.flush().then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      out.busy = false;
      if (!identical(_out[socket], out)) return;
      final link = out.link;
      if (frames > 0 && link != null) onEvent?.call(FramesSent(link, frames));
      _flush(socket, out);
    });
  }

  void _end(int link) {
    final socket = _sockets.remove(link);
    if (socket == null) return;
    _out.remove(socket);
    _lastHeard.remove(link);
    _linkOf.removeWhere((_, other) => other == link);
    socket.destroy();
    onEvent?.call(LinkDown(link));
  }

  @override
  void send(int link, List<String> frames) {
    final socket = _sockets[link];
    if (socket == null) return;
    for (final frame in frames) {
      _write(socket, _bytes(frame), link: link);
    }
  }

  @override
  void drop(int link) => _end(link);

  static String _hex(Uint8List bytes) {
    final out = StringBuffer();
    for (final byte in bytes) {
      out.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  static Uint8List _bytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

/// What is waiting to be written to one connection.
class _Out {
  final List<List<int>> waiting = [];

  /// Frames the app sent among [waiting].
  int frames = 0;

  /// Whether a batch is on its way to the network.
  bool busy = false;
  int? link;
}

/// Two radios run as one: Bluetooth, and the local network beside it.
///
/// The app is told about links on either. Whether the radio is "working"
/// is Bluetooth's word, since that is the one that reaches a device
/// sharing no network; except that a device with no Bluetooth at all is
/// counted as working if the network link is.
class MultiRadio extends Radio {
  MultiRadio(this._bluetooth, this._network, {LoRaRadio? lora}) {
    _bluetooth.onEvent = (event) {
      if (event is RadioChanged) {
        _bluetoothState = event.state;
        _report();
      } else {
        onEvent?.call(event);
      }
    };
    _network.onEvent = (event) {
      if (event is RadioChanged) {
        _networkOn = event.state == RadioState.on;
        _report();
      } else {
        onEvent?.call(event);
      }
    };
    _hookLora(lora);
  }

  final Radio _bluetooth;
  final Radio _network;
  LoRaRadio? _lora;
  RadioState _bluetoothState = RadioState.off;
  bool _networkOn = false;
  bool _loraOn = false;
  bool _wantNetwork = true;
  bool _wantLora = false;
  bool _running = false;

  /// The LoRa radio beside the two, if one is set up.
  LoRaRadio? get lora => _lora;

  void _hookLora(LoRaRadio? lora) {
    _lora = lora;
    lora?.onEvent = (event) {
      if (event is RadioChanged) {
        _loraOn = event.state == RadioState.on;
        _report();
      } else {
        onEvent?.call(event);
      }
    };
  }

  /// Puts a LoRa radio in, or takes it out with null. The old one is
  /// stopped, so every link over it closes; the new one starts if the
  /// user has the long-range link switched on.
  Future<void> setLora(LoRaRadio? next) async {
    final old = _lora;
    if (identical(old, next)) return;
    if (old != null) {
      await old.stop();
      old.onEvent = null;
      _loraOn = false;
    }
    _hookLora(next);
    if (next != null && _running && _wantLora) await next.start();
    _report();
  }

  /// Whether the LoRa radio is up.
  bool get loraOn => _loraOn;

  void _report() => onEvent?.call(
    RadioChanged(
      _bluetoothState == RadioState.unsupported && (_networkOn || _loraOn)
          ? RadioState.on
          : _bluetoothState,
    ),
  );

  /// Switches the LoRa radio on or off, as the user chooses under
  /// Network. Nothing else is touched.
  Future<void> useLora(bool on) async {
    _wantLora = on;
    final lora = _lora;
    if (lora == null || !_running) return;
    if (on) {
      await lora.start();
    } else {
      await lora.stop();
      _loraOn = false;
    }
  }

  /// Switches the local network link on or off, as the user chooses under
  /// Network. Bluetooth is not touched.
  Future<void> useNetwork(bool on) async {
    if (_wantNetwork == on) return;
    _wantNetwork = on;
    if (!_running) return;
    if (on) {
      await _network.start();
    } else {
      await _network.stop();
      _networkOn = false;
    }
  }

  @override
  Future<void> start() async {
    _running = true;
    await _bluetooth.start();
    if (_wantNetwork) await _network.start();
    if (_wantLora) await _lora?.start();
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _bluetooth.stop();
    await _network.stop();
    await _lora?.stop();
    _networkOn = false;
    _loraOn = false;
  }

  Radio _for(int link) => switch (LinkNumbers.of(link)) {
    Transport.wifi => _network,
    Transport.bluetooth => _bluetooth,
    Transport.radio => _lora ?? _bluetooth,
  };

  @override
  void send(int link, List<String> frames) => _for(link).send(link, frames);

  @override
  void drop(int link) => _for(link).drop(link);

  @override
  Future<bool> askPermission() => _bluetooth.askPermission();

  @override
  void reach(String address) {
    if (_wantNetwork) _network.reach(address);
  }
}
