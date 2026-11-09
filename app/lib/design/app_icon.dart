import 'package:flutter/widgets.dart';

import 'svg_path.dart';

/// One drawable piece of an icon.
sealed class IconShape {
  const IconShape();
}

class IconPath extends IconShape {
  const IconPath(this.data);
  final String data;
}

class IconCircle extends IconShape {
  const IconCircle(this.cx, this.cy, this.r, {this.filled = false});
  final double cx, cy, r;

  /// Filled as well as outlined, whatever the icon's own fill setting.
  final bool filled;
}

class IconRect extends IconShape {
  const IconRect(this.x, this.y, this.width, this.height, {this.rx = 0});
  final double x, y, width, height, rx;
}

/// An icon from the design kit, drawn on a 24 unit grid.
class AppIconData {
  const AppIconData(this.shapes);
  final List<IconShape> shapes;
}

/// Draws a [AppIconData] as an outline with round caps and joins.
///
/// The stroke scales with [size], as it does in the reference SVG: a 2 unit
/// stroke on the 24 unit grid is 1.83 px wide at size 22.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 22,
    this.color,
    this.strokeWidth = 2,
    this.filled = false,
    this.semanticLabel,
  });

  final AppIconData icon;
  final double size;

  /// Defaults to the surrounding text colour, like `currentColor` in SVG.
  final Color? color;
  final double strokeWidth;

  /// Fill every shape as well as stroking it.
  final bool filled;

  /// Read out by screen readers. When null the icon is decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFFFFFFFF);
    final paint = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _AppIconPainter(icon, resolved, strokeWidth, filled),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _AppIconPainter extends CustomPainter {
  _AppIconPainter(this.icon, this.color, this.strokeWidth, this.filled);

  final AppIconData icon;
  final Color color;
  final double strokeWidth;
  final bool filled;

  static final Map<String, Path> _paths = {};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    for (final shape in icon.shapes) {
      switch (shape) {
        case IconPath(:final data):
          final path = _paths[data] ??= parseSvgPath(data);
          if (filled) canvas.drawPath(path, fill);
          canvas.drawPath(path, stroke);
        case IconCircle(:final cx, :final cy, :final r, filled: final dot):
          final centre = Offset(cx, cy);
          if (filled || dot) canvas.drawCircle(centre, r, fill);
          canvas.drawCircle(centre, r, stroke);
        case IconRect(
          :final x,
          :final y,
          :final width,
          :final height,
          :final rx,
        ):
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, width, height),
            Radius.circular(rx),
          );
          if (filled) canvas.drawRRect(rect, fill);
          canvas.drawRRect(rect, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_AppIconPainter old) =>
      old.icon != icon ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.filled != filled;
}
