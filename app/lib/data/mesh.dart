import 'package:flutter/foundation.dart';

import 'models.dart';

/// Which radio a map of the mesh shows.
enum MeshRadio { bluetooth, wifi }

/// A link between two devices: either one can hand a message to the other.
@immutable
class MeshLink {
  const MeshLink(
    this.a,
    this.b, {
    this.bluetooth = false,
    this.wifi = false,
    this.near,
  });

  final String a;
  final String b;
  final bool bluetooth;

  /// The same Wi-Fi, or Wi-Fi Direct.
  final bool wifi;

  /// How strongly one end hears the other, where that is known.
  final Nearness? near;

  bool on(MeshRadio radio) => switch (radio) {
    MeshRadio.bluetooth => bluetooth,
    MeshRadio.wifi => wifi,
  };

  bool touches(String id) => a == id || b == id;

  String other(String id) => id == a ? b : a;
}

/// One step of a route: the device a message is handed to, and how.
@immutable
class MeshHop {
  const MeshHop(this.to, this.radio, this.near);
  final String to;
  final MeshRadio radio;
  final Nearness? near;
}

/// The way a message to someone would go right now: each device it is
/// handed to, in order, the last being them.
@immutable
class MeshRoute {
  const MeshRoute(this.hops);
  final List<MeshHop> hops;

  String get to => hops.last.to;
  bool get direct => hops.length == 1;

  /// The devices in between, nearest first.
  List<String> get through => [
    for (final hop in hops.take(hops.length - 1)) hop.to,
  ];

  /// Every device on the way, this one ([Mesh.me]) first.
  List<String> get path => [Mesh.me, for (final hop in hops) hop.to];
}

/// The mesh as this device knows it: who it hears itself, and who those
/// devices said they hear. It changes whenever anyone comes, goes or moves.
class Mesh {
  /// Links between the same two devices are merged into one.
  Mesh(Iterable<MeshLink> links, {this.ends = const {}})
    : links = _merge(links);

  /// This device, on every map.
  static const me = '';

  /// As far as a message can travel, in links. The same as the core's.
  static const reach = 5;

  final List<MeshLink> links;

  /// Devices that pass nothing on for others: a route can end at one, but
  /// never goes through it.
  final Set<String> ends;

  static List<MeshLink> _merge(Iterable<MeshLink> links) {
    final merged = <(String, String), MeshLink>{};
    for (final link in links) {
      if (link.a == link.b) continue;
      final pair = link.a.compareTo(link.b) < 0
          ? (link.a, link.b)
          : (link.b, link.a);
      final had = merged[pair];
      merged[pair] = had == null
          ? link
          : MeshLink(
              had.a,
              had.b,
              bluetooth: had.bluetooth || link.bluetooth,
              wifi: had.wifi || link.wifi,
              // What was given first wins: this device's own reading.
              near: had.near ?? link.near,
            );
    }
    return List.unmodifiable(merged.values);
  }

  late final Map<String, List<MeshLink>> _around = () {
    final around = <String, List<MeshLink>>{};
    for (final link in links) {
      (around[link.a] ??= []).add(link);
      (around[link.b] ??= []).add(link);
    }
    return around;
  }();

  final Map<MeshRadio?, Map<String, MeshRoute>> _routes = {};

  /// The shortest way to every device, by device, as a message would go
  /// right now. Of two equally short ways the one on Wi-Fi, then the one
  /// heard more strongly, wins.
  ///
  /// With a [radio], only ways that start on it: the devices in range on
  /// that radio and whoever they reach, by either radio, keeping to the
  /// same radio where they can. That is what the radio's map shows.
  Map<String, MeshRoute> routes([MeshRadio? radio]) =>
      _routes[radio] ??= _search(radio);

  MeshRoute? routeTo(String id, [MeshRadio? radio]) => routes(radio)[id];

  Map<String, MeshRoute> _search(MeshRadio? radio) {
    final found = <String, MeshRoute>{};
    var edge = [const MeshRoute([])];
    for (var depth = 0; depth < reach && edge.isNotEmpty; depth++) {
      final next = <MeshRoute>[];
      for (final route in edge) {
        final at = route.hops.isEmpty ? me : route.to;
        if (at != me && ends.contains(at)) continue;
        final choices = [
          for (final link in _around[at] ?? const <MeshLink>[])
            if (at != me || radio == null || link.on(radio)) link,
        ]..sort((x, y) => _better(x, y, at, radio));
        for (final link in choices) {
          final to = link.other(at);
          if (to == me || found.containsKey(to)) continue;
          final hop = MeshHop(
            to,
            radio != null && link.on(radio)
                ? radio
                : link.wifi
                ? MeshRadio.wifi
                : MeshRadio.bluetooth,
            link.near,
          );
          next.add(found[to] = MeshRoute([...route.hops, hop]));
        }
      }
      edge = next;
    }
    return found;
  }

  static int _better(MeshLink x, MeshLink y, String from, MeshRadio? radio) {
    if (radio != null && x.on(radio) != y.on(radio)) {
      return x.on(radio) ? -1 : 1;
    }
    if (x.wifi != y.wifi) return x.wifi ? -1 : 1;
    final near = _rank(x.near).compareTo(_rank(y.near));
    return near != 0 ? near : x.other(from).compareTo(y.other(from));
  }

  static int _rank(Nearness? near) => near?.index ?? Nearness.values.length;

  /// The links to draw on [radio]'s map: this device's own on that radio,
  /// and any between devices on the map.
  List<MeshLink> linksFor(MeshRadio radio) {
    final shown = routes(radio);
    return [
      for (final link in links)
        if (link.touches(me)
            ? link.on(radio) && shown.containsKey(link.other(me))
            : shown.containsKey(link.a) && shown.containsKey(link.b))
          link,
    ];
  }

  /// The mesh drawn from what a list of people says about each: whom
  /// this device hears itself, and who was reached through whom. Where
  /// nothing more is known, that is all there is.
  factory Mesh.fromPeople(
    Iterable<Person> people, {
    Nearness? Function(String id)? nearness,
  }) => Mesh([
    for (final person in people)
      if (person.link.kind case LinkKind.wifi || LinkKind.bluetooth)
        MeshLink(
          me,
          person.id,
          wifi: person.link.kind == LinkKind.wifi,
          bluetooth: person.link.kind == LinkKind.bluetooth,
          near: nearness?.call(person.id),
        )
      else if (person.link case PersonLink(
        kind: LinkKind.relayed,
        hops: 2,
        :final viaId?,
      ))
        MeshLink(viaId, person.id, bluetooth: true),
  ]);
}
