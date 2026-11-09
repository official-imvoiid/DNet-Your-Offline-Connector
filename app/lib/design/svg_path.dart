import 'dart:ui';

final _token = RegExp(
  r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
);

/// Builds a [Path] from SVG path data, such as `M12 5v14M5 12h14`.
///
/// Supports the full SVG path command set. Throws a [FormatException] on
/// malformed data, because icon data is fixed at build time and a bad path is
/// a bug to fix, not a state to recover from.
Path parseSvgPath(String data) {
  final tokens = _token.allMatches(data).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  var command = '';
  // Current point, start of the current subpath, and the last control point
  // (kept only while the previous command was a curve of the same family).
  double x = 0, y = 0, startX = 0, startY = 0;
  double? cubicX, cubicY, quadX, quadY;

  bool isCommand(String t) => t.length == 1 && RegExp(r'[A-Za-z]').hasMatch(t);

  double next() {
    if (i >= tokens.length || isCommand(tokens[i])) {
      throw FormatException('Path data ends mid-command', data);
    }
    return double.parse(tokens[i++]);
  }

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      command = tokens[i++];
      if (command == 'Z' || command == 'z') {
        path.close();
        x = startX;
        y = startY;
        cubicX = cubicY = quadX = quadY = null;
        continue;
      }
    } else if (command.isEmpty) {
      throw FormatException('Path data must start with a command', data);
    }

    final relative = command == command.toLowerCase();
    final dx = relative ? x : 0.0;
    final dy = relative ? y : 0.0;
    double? nextCubicX, nextCubicY, nextQuadX, nextQuadY;

    switch (command.toUpperCase()) {
      case 'M':
        x = next() + dx;
        y = next() + dy;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Further coordinate pairs after a move are implicit lines.
        command = relative ? 'l' : 'L';
      case 'L':
        x = next() + dx;
        y = next() + dy;
        path.lineTo(x, y);
      case 'H':
        x = next() + dx;
        path.lineTo(x, y);
      case 'V':
        y = next() + dy;
        path.lineTo(x, y);
      case 'C':
        final x1 = next() + dx, y1 = next() + dy;
        final x2 = next() + dx, y2 = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        nextCubicX = x2;
        nextCubicY = y2;
      case 'S':
        // The first control point mirrors the previous curve's second one.
        final x1 = cubicX == null ? x : 2 * x - cubicX;
        final y1 = cubicY == null ? y : 2 * y - cubicY;
        final x2 = next() + dx, y2 = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        nextCubicX = x2;
        nextCubicY = y2;
      case 'Q':
        final x1 = next() + dx, y1 = next() + dy;
        x = next() + dx;
        y = next() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        nextQuadX = x1;
        nextQuadY = y1;
      case 'T':
        final x1 = quadX == null ? x : 2 * x - quadX;
        final y1 = quadY == null ? y : 2 * y - quadY;
        x = next() + dx;
        y = next() + dy;
        path.quadraticBezierTo(x1, y1, x, y);
        nextQuadX = x1;
        nextQuadY = y1;
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final largeArc = next() != 0, sweep = next() != 0;
        x = next() + dx;
        y = next() + dy;
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y);
        } else {
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx.abs(), ry.abs()),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
        }
      default:
        throw FormatException('Unknown path command "$command"', data);
    }

    cubicX = nextCubicX;
    cubicY = nextCubicY;
    quadX = nextQuadX;
    quadY = nextQuadY;
  }
  return path;
}
