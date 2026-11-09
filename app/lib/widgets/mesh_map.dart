import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../data/mesh.dart';
import '../data/models.dart';
import '../design/tokens.dart';

/// How a device is drawn on a map.
typedef MeshFace = ({String name, String initial, AvatarTone tone});

/// Where each device sits on a map of one radio, on a square two units
/// across with this device in the middle.
///
/// The devices it hears are on the first ring, nearer the middle the more
/// strongly they are heard. Each further hop is one ring further out,
/// fanned out behind the device that reaches it. Bluetooth cannot tell
/// which way anyone is, so the angles only keep everyone apart and steady.
class MeshLayout {
  MeshLayout(this.mesh, this.radio) {
    _place();
  }

  final Mesh mesh;
  final MeshRadio radio;

  /// By device, [Mesh.me] included.
  final Map<String, Offset> at = {};

  /// How far apart the rings are.
  late final double step;

  /// The deepest ring in use.
  int depth = 0;

  late final Map<String, MeshRoute> routes = mesh.routes(radio);

  /// The device each one is reached through, or [Mesh.me].
  String parentOf(String id) {
    final hops = routes[id]?.hops;
    return hops == null || hops.length < 2 ? Mesh.me : hops[hops.length - 2].to;
  }

  void _place() {
    at[Mesh.me] = Offset.zero;
    final children = <String, List<String>>{};
    for (final MapEntry(:key, value: route) in routes.entries) {
      depth = math.max(depth, route.hops.length);
      (children[parentOf(key)] ??= []).add(key);
    }
    step = 0.9 / math.max(depth, 1);
    // How many devices hang off each, to share out the room fairly.
    final weight = <String, int>{};
    int weigh(String id) => weight[id] ??= math.max(
      1,
      (children[id] ?? const <String>[]).fold(0, (sum, c) => sum + weigh(c)),
    );
    for (final kids in children.values) {
      kids.sort((a, b) => _turn(a).compareTo(_turn(b)));
    }
    void spread(String id, double from, double width, int ring) {
      final kids = children[id] ?? const <String>[];
      if (kids.isEmpty) return;
      final total = kids.fold(0, (sum, kid) => sum + weigh(kid));
      var start = from;
      for (final kid in kids) {
        final share = width * weigh(kid) / total;
        final angle = start + share / 2;
        final hop = routes[kid]!.hops.last;
        final radius = step * (ring - 1 + _out(hop.near, first: ring == 1));
        at[kid] = Offset(math.cos(angle), math.sin(angle)) * radius;
        // Further out, the fan narrows, so whoever is reached through
        // someone stays near them.
        final room = math.min(share, math.pi / (ring + 0.5));
        spread(kid, angle - room / 2, room, ring + 1);
        start += share;
      }
    }

    spread(Mesh.me, -math.pi / 2, 2 * math.pi, 1);
  }

  /// A steady spot on the circle for each device, from its key.
  static double _turn(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0xFFFFFF;
    }
    return hash / 0xFFFFFF;
  }

  /// How far along its ring step a device sits, from how strongly it is
  /// heard.
  static double _out(Nearness? near, {required bool first}) => switch (near) {
    Nearness.veryClose => first ? 0.5 : 0.8,
    Nearness.near => first ? 0.75 : 0.92,
    Nearness.far => 1.0,
    null => first ? 0.85 : 1.0,
  };

  /// [unit], as a point on a map [size] across.
  static Offset toPixels(Offset unit, Size size) {
    final half = size.shortestSide / 2;
    return size.center(Offset.zero) + unit * (half - 18);
  }
}

/// A live map of the mesh on one radio. Tapping a device picks it, and
/// the way a message to it would go is drawn over the rest.
class MeshMap extends StatefulWidget {
  const MeshMap({
    super.key,
    required this.mesh,
    required this.radio,
    required this.faceOf,
    required this.label,
    this.selected,
    this.onSelect,
  });

  final Mesh mesh;
  final MeshRadio radio;
  final MeshFace Function(String id) faceOf;

  /// What a screen reader says the map shows.
  final String label;
  final String? selected;
  final ValueChanged<String?>? onSelect;

  @override
  State<MeshMap> createState() => _MeshMapState();
}

class _MeshMapState extends State<MeshMap> with SingleTickerProviderStateMixin {
  late MeshLayout _layout = MeshLayout(widget.mesh, widget.radio);
  Map<String, Offset> _from = const {};
  late final _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  @override
  void didUpdateWidget(MeshMap old) {
    super.didUpdateWidget(old);
    if (identical(old.mesh, widget.mesh) && old.radio == widget.radio) return;
    final now = _positions(Curves.easeOut.transform(_move.value));
    final next = MeshLayout(widget.mesh, widget.radio);
    final moved =
        next.at.length != _layout.at.length ||
        next.at.entries.any(
          (e) => ((now[e.key] ?? Offset.infinite) - e.value).distance > 0.002,
        );
    _layout = next;
    if (!moved) return;
    // Whoever is new comes out from the device that reaches them.
    _from = {
      for (final id in next.at.keys)
        id: now[id] ?? now[next.parentOf(id)] ?? Offset.zero,
    };
    _move.forward(from: 0);
  }

  Map<String, Offset> _positions(double t) => {
    for (final MapEntry(:key, :value) in _layout.at.entries)
      key: Offset.lerp(_from[key] ?? value, value, t)!,
  };

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  String? _hit(Offset point, Size size) {
    String? best;
    var nearest = 30.0;
    for (final MapEntry(:key, :value) in _layout.at.entries) {
      if (key == Mesh.me) continue;
      final distance = (MeshLayout.toPixels(value, size) - point).distance;
      if (distance < nearest) (best, nearest) = (key, distance);
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size.square(
            math.min(constraints.maxWidth, constraints.maxHeight),
          );
          return Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: widget.onSelect == null
                  ? null
                  : (tap) => widget.onSelect!(_hit(tap.localPosition, size)),
              child: AnimatedBuilder(
                animation: _move,
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: _MeshPainter(
                    layout: _layout,
                    at: _positions(Curves.easeOut.transform(_move.value)),
                    faceOf: widget.faceOf,
                    selected: widget.selected,
                    direction: Directionality.of(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.layout,
    required this.at,
    required this.faceOf,
    required this.selected,
    required this.direction,
  });

  final MeshLayout layout;
  final Map<String, Offset> at;
  final MeshFace Function(String id) faceOf;
  final String? selected;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    Offset px(String id) => MeshLayout.toPixels(at[id] ?? Offset.zero, size);
    final centre = px(Mesh.me);
    final scale = size.shortestSide / 2 - 18;
    final ring = layout.step * scale;
    final count = at.length;
    final dot = (size.shortestSide / (count > 24 ? 30 : 22)).clamp(9.0, 16.0);
    final route = selected == null ? null : layout.routes[selected];
    final onRoute = {...?route?.path};

    // The rings, one for each hop out.
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..color = AppColors.line;
    for (var d = 1; d <= math.max(layout.depth, 1); d++) {
      canvas.drawCircle(centre, ring * d, faint);
    }

    // Each device's own range: how far its radio carries, roughly one
    // ring. This device's is tinted.
    canvas.drawCircle(
      centre,
      ring,
      Paint()..color = AppColors.accent.withValues(alpha: 0.07),
    );
    final range = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final id in at.keys) {
      if (id == Mesh.me) continue;
      range.color = onRoute.contains(id)
          ? AppColors.accent.withValues(alpha: 0.35)
          : AppColors.text3.withValues(alpha: 0.16);
      canvas.drawCircle(px(id), ring * 0.9, range);
    }

    // Links between neighbours. A hop on the other radio is dashed; a
    // weak one is fainter.
    for (final link in layout.mesh.linksFor(layout.radio)) {
      if (!at.containsKey(link.a) || !at.containsKey(link.b)) continue;
      final (a, b) = (px(link.a), px(link.b));
      final tree =
          layout.parentOf(link.b) == link.a ||
          layout.parentOf(link.a) == link.b;
      final paint = Paint()
        ..strokeWidth = tree ? 1.6 : 1
        ..strokeCap = StrokeCap.round
        ..color = AppColors.text3.withValues(
          alpha: (tree ? 0.7 : 0.35) * (link.near == Nearness.far ? 0.6 : 1),
        );
      if (link.on(layout.radio)) {
        canvas.drawLine(a, b, paint);
      } else {
        _dashed(canvas, a, b, paint);
      }
    }

    // The way a message to whoever is picked would go.
    if (route != null) {
      final path = Path()..moveTo(centre.dx, centre.dy);
      for (final hop in route.hops) {
        final point = px(hop.to);
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = AppColors.accent,
      );
    }

    // This device.
    canvas
      ..drawCircle(centre, 16, Paint()..color = AppColors.accentSoft)
      ..drawCircle(centre, 11, Paint()..color = AppColors.accent);

    // Everyone else, with a name under those in range or on the way.
    final labelled = count <= 14;
    for (final id in at.keys) {
      if (id == Mesh.me) continue;
      final face = faceOf(id);
      final point = px(id);
      final first = layout.routes[id]?.hops.length == 1;
      final radius = first ? dot : dot * 0.82;
      if (onRoute.contains(id)) {
        canvas.drawCircle(
          point,
          radius + (id == selected ? 4.5 : 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = id == selected ? 2.5 : 1.5
            ..color = AppColors.accent,
        );
      }
      canvas
        ..drawCircle(point, radius + 2, Paint()..color = AppColors.surface)
        ..drawCircle(point, radius, Paint()..color = face.tone.background);
      _text(
        canvas,
        face.initial,
        point,
        AppText.base.copyWith(
          fontSize: radius * 0.85,
          fontWeight: FontWeight.w700,
          color: face.tone.foreground,
          height: 1,
        ),
        centred: true,
      );
      if (labelled || first || onRoute.contains(id)) {
        _text(
          canvas,
          face.name,
          point + Offset(0, radius + 4),
          AppText.base.copyWith(
            fontSize: 11,
            height: 1.2,
            fontWeight: id == selected ? FontWeight.w700 : FontWeight.w500,
            color: id == selected ? AppColors.text : AppColors.text2,
          ),
          maxWidth: 84,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    bool centred = false,
    double maxWidth = 200,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(
      canvas,
      at - Offset(painter.width / 2, centred ? painter.height / 2 : 0),
    );
    painter.dispose();
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final length = (b - a).distance;
    if (length == 0) return;
    final along = (b - a) / length;
    for (var d = 0.0; d < length; d += 7) {
      canvas.drawLine(
        a + along * d,
        a + along * math.min(d + 4, length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.layout != layout ||
      old.faceOf != faceOf ||
      old.selected != selected ||
      old.at.length != at.length ||
      old.at.entries.any((e) => at[e.key] != e.value);
}
