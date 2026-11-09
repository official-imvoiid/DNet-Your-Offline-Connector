import '../core/core_bridge.dart';
import '../radio/link_pump.dart';
import 'mesh.dart';
import 'models.dart';

/// One device in range, as this device hears it.
typedef MeshPeer = ({String key, bool bluetooth, bool wifi, Nearness? near});

/// Tells the devices in range who this one hears, and reads back what they
/// told of theirs, so the Nearby maps reach past the radio's own range.
///
/// What goes out is decided by the core: signing keys only, never names,
/// nobody who chose to be invisible, and only news or the same again now
/// and then. See `relay.rs` in the core.
class LiveMesh {
  LiveMesh(this._bridge, this._pump);

  final CoreBridge _bridge;
  final LinkPump _pump;

  /// The user's own signing key, once looked up.
  String? _me;

  /// Tells each device in range that is due it who this one hears.
  void share(Iterable<MeshPeer> peers) {
    try {
      _pump.sendDeliveries(
        _bridge.call({
          'op': 'mesh_share',
          'peers': [
            for (final peer in peers)
              {
                'key': peer.key,
                'bluetooth': peer.bluetooth,
                'wifi': peer.wifi,
                'near': _toWire(peer.near),
              },
          ],
        }),
      );
    } on CoreException {
      // No identity yet, or nothing open: nobody to tell.
    }
  }

  /// The mesh: this device's [own] links, what the devices in range told,
  /// and any [more] the app worked out itself.
  Mesh read(List<MeshLink> own, {List<MeshLink> more = const []}) {
    final Object? reply;
    try {
      _me ??= switch (_bridge.call({'op': 'profile'})) {
        {'signing_key': final String key} => key,
        _ => null,
      };
      reply = _bridge.call({'op': 'mesh'});
    } on CoreException {
      return Mesh([...own, ...more]);
    }
    if (reply is! Map<String, Object?>) return Mesh([...own, ...more]);
    final told = <MeshLink>[];
    for (final link in (reply['links'] as List? ?? const []).cast<Map>()) {
      final (from, to) = (link['from'], link['to']);
      // This device's own links are known first-hand.
      if (from is! String || to is! String || from == _me || to == _me) {
        continue;
      }
      told.add(
        MeshLink(
          from,
          to,
          bluetooth: link['bluetooth'] == true,
          wifi: link['wifi'] == true,
          near: _fromWire(link['near']),
        ),
      );
    }
    // What the app worked out itself only fills gaps: what devices said
    // is better.
    String pair(MeshLink link) => link.a.compareTo(link.b) < 0
        ? '${link.a} ${link.b}'
        : '${link.b} ${link.a}';
    final known = {
      for (final link in [...own, ...told]) pair(link),
    };
    return Mesh(
      [
        ...own,
        ...told,
        for (final link in more)
          if (!known.contains(pair(link))) link,
      ],
      ends: {...(reply['ends'] as List? ?? const []).cast<String>()},
    );
  }

  static int _toWire(Nearness? near) => switch (near) {
    null => 0,
    Nearness.veryClose => 1,
    Nearness.near => 2,
    Nearness.far => 3,
  };

  static Nearness? _fromWire(Object? near) => switch (near) {
    1 => Nearness.veryClose,
    2 => Nearness.near,
    3 => Nearness.far,
    _ => null,
  };
}
