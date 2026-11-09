import 'dart:async';

import 'direct_wifi.dart';

/// Gets two devices that share no network onto one, with Wi-Fi Direct, so
/// that something big need not crawl over Bluetooth.
///
/// One of the two makes a group and the other joins it. Which does which
/// is settled in two short messages over the link they already have, both
/// sealed by the core like any other:
///
/// - a device that can join one asks the other to make it;
/// - a device that cannot (a PC) makes it itself and says so;
/// - if both made one at the same moment, the one with the lower number
///   keeps theirs, unless the other could not join it anyway.
///
/// This class decides only that, and which band the group goes on.
/// Making and joining the group is the device's job ([DirectWifi]),
/// sending the two messages is the core's, and once both are on the group
/// the network radio does the rest.
///
/// A device that can choose ([DirectWifi.canChooseBand]) makes its group
/// on the quieter band, where it can tell which that is. If someone it
/// offered the group to is still not reached over it when next it is
/// wanted, the band is taken to be too crowded: the group is made again on
/// the other band, and offered again. Windows cannot choose, so a group a
/// PC makes stays wherever Windows put it.
///
/// Not yet verified on devices.
class FastLink {
  FastLink({
    required this.wifi,
    required this.myId,
    required this.ask,
    required this.offer,
    required this.greet,
    DateTime Function()? clock,
    this.tryEvery = const Duration(seconds: 30),
    this.answerEvery = const Duration(seconds: 10),
    this.restFor = const Duration(minutes: 2),
    this.lookEvery = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  final DirectWifi wifi;

  /// The user's own id. Only ever compared with the other device's, to
  /// settle which gives way.
  final String myId;

  /// Sends "can we use something faster?" to someone in range.
  final void Function(String to) ask;

  /// Sends them the group this device made.
  final void Function(String to, DirectGroup group, {required bool joins})
  offer;

  /// Tells the network radio an address to say hello to.
  final void Function(String address) greet;

  final DateTime Function() _clock;

  /// How long before the same person is tried again.
  final Duration tryEvery;

  /// How long before the same person is answered again. Someone who asks
  /// over and over is not made a new offer each time.
  final Duration answerEvery;

  /// How long a group is kept once nothing big is moving.
  final Duration restFor;

  /// How often a device that made a group looks for who has joined.
  final Duration lookEvery;

  DirectGroup? _hosting;

  /// The band the group this device made is on, if it chose one.
  WifiBand? _band;

  /// The band the next group is to be made on, once one was too crowded.
  WifiBand? _nextBand;

  /// Who has been offered the group this device made.
  final Set<String> _offeredTo = {};

  /// Who made the group this device joined.
  String? _joinedFrom;

  /// Each time a group was made again on the other band: for whom, onto
  /// which band, and when. Newest last.
  final List<BandMove> moves = [];

  /// The group this device joined, and where on it the device that made
  /// it is.
  DirectGroup? _joinedGroup;
  String? _makerAddress;
  bool get _joined => _joinedGroup != null;
  final Map<String, DateTime> _tried = {};
  final Map<String, DateTime> _answered = {};
  Timer? _looking;
  Timer? _resting;

  /// One thing at a time: making, joining and leaving a group each take
  /// a while, and two of them at once would trip over each other.
  Future<void> _turn = Future.value();

  Future<void> _next(Future<void> Function() work) =>
      _turn = _turn.then((_) => work());

  bool _due(Map<String, DateTime> last, String who, Duration every) {
    final now = _clock();
    final before = last[who];
    if (before != null && now.difference(before) < every) return false;
    last[who] = now;
    return true;
  }

  /// Something big is moving to or from [peer], who is in range but
  /// reached only over Bluetooth.
  void want(String peer) {
    if (_joined && _joinedFrom != peer) return;
    if (!_due(_tried, peer, tryEvery)) return;
    _resting?.cancel();
    _resting = null;
    if (_joined) {
      // On their group, and still no link to them over it: it is not
      // carrying. Leave it and ask again, so whoever made it can move it.
      _next(() async {
        await _leave();
        ask(peer);
      });
      return;
    }
    if (_crowded(peer)) {
      _next(() => _changeBand(peer));
    } else if (_hosting == null && wifi.canJoin) {
      ask(peer);
    } else {
      _next(() => _offerTo(peer));
    }
  }

  /// [from] asked for a faster link.
  Future<void> asked(String from) {
    if (!_due(_answered, from, answerEvery)) return Future.value();
    if (_crowded(from)) return _next(() => _changeBand(from));
    return _next(() => _offerTo(from));
  }

  /// Whether [peer] was offered the group this device made and still
  /// wants a faster link: the group is not reaching them. If the device
  /// can choose, that is taken for a crowded band.
  bool _crowded(String peer) =>
      _hosting != null && _offeredTo.contains(peer) && wifi.canChooseBand;

  /// Makes the group again on the other band, and offers it to [peer].
  /// Anyone else on the old group is offered the new one when next they
  /// want it.
  Future<void> _changeBand(String peer) async {
    if (_hosting == null) return _offerTo(peer);
    final from = _band;
    await _leave();
    final to = from?.other ?? await wifi.quieterBand() ?? WifiBand.high;
    _nextBand = to;
    moves.add(BandMove(peer, to, _clock()));
    if (moves.length > 20) moves.removeAt(0);
    await _offerTo(peer);
  }

  Future<void> _offerTo(String peer) async {
    // A device that joined someone's group cannot make one as well.
    if (_joined) return;
    var group = _hosting;
    if (group == null) {
      group = DirectGroup.fresh();
      var band = wifi.canChooseBand
          ? _nextBand ?? await wifi.quieterBand()
          : null;
      var made = await wifi.host(group, band: band);
      if (!made && band != null) {
        // Not on that band, perhaps one this device does not have. Let
        // it choose.
        band = null;
        made = await wifi.host(group);
      }
      if (!made) return;
      _hosting = group;
      _band = band;
      _looking = Timer.periodic(lookEvery, (_) => _look());
    }
    _offeredTo.add(peer);
    offer(peer, group, joins: wifi.canJoin);
  }

  /// [from] made a group and says to join it. [theyJoin] is whether they
  /// could have joined one instead.
  Future<void> offered(String from, DirectGroup group, bool theyJoin) =>
      _next(() async {
        if (!wifi.canJoin) return;
        if (_hosting != null) {
          // Both made one. The lower number keeps theirs and the other
          // joins it, unless the other is unable to.
          if (theyJoin && myId.compareTo(from) < 0) return;
          await _leave();
        }
        if (_joined) {
          // Told again of the group this device is already on. The group
          // is not what is wrong: the link over it has not come up. So
          // it says hello again, and does not leave only to come back.
          if (group == _joinedGroup) return greet(_makerAddress!);
          await _leave();
        }
        final address = await wifi.join(group);
        if (address == null) return;
        _joinedGroup = group;
        _joinedFrom = from;
        _makerAddress = address;
        greet(address);
      });

  Future<void> _look() async {
    if (_hosting == null) return;
    for (final address in await wifi.members()) {
      greet(address);
    }
  }

  /// Whether anything big is moving. When nothing is, the group is given
  /// up after a while: it costs battery, and on a phone it can get in the
  /// way of other uses of Wi-Fi Direct.
  void moving(bool anything) {
    if (anything) {
      _resting?.cancel();
      _resting = null;
    } else if ((_hosting != null || _joined) && _resting == null) {
      _resting = Timer(restFor, () {
        _resting = null;
        _next(_leave);
      });
    }
  }

  Future<void> _leave() async {
    _looking?.cancel();
    _looking = null;
    _hosting = null;
    _band = null;
    _offeredTo.clear();
    _joinedGroup = null;
    _joinedFrom = null;
    _makerAddress = null;
    await wifi.leave();
  }

  /// Gives up any group now. Used when the user switches the fast link
  /// off, and when the app shuts.
  Future<void> stop() {
    _resting?.cancel();
    _resting = null;
    return _next(() async {
      if (_hosting != null || _joined) await _leave();
    });
  }
}

/// A group made again on the other band, because the one it was on did
/// not reach [peer].
class BandMove {
  const BandMove(this.peer, this.band, this.at);
  final String peer;
  final WifiBand band;
  final DateTime at;
}
