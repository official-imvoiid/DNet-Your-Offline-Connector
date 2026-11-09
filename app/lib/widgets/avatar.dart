import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../design/app_icon.dart';
import '../design/tokens.dart';

/// A person (circle) or a space (rounded square) shown as initials or an icon
/// on one of the eight avatar colour pairs.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.tone,
    this.label = '',
    this.icon,
    this.iconSize,
    this.size = 48,
    this.square = false,
    this.fontSize,
    this.fontWeight = FontWeight.w700,
    this.online = false,
    this.surround = AppColors.bg,
    this.ringColor,
    this.ringWidth = 3,
    this.gap = false,
    this.photo,
  });

  /// A profile photo or GIF to show instead of the letters.
  final Uint8List? photo;

  final AvatarTone tone;

  /// One or two letters. Ignored when [icon] is set.
  final String label;
  final AppIconData? icon;
  final double? iconSize;
  final double size;

  /// Spaces are rounded squares with a radius of one third of the size.
  final bool square;

  /// Defaults to 40 percent of the size.
  final double? fontSize;
  final FontWeight fontWeight;

  /// Shows the green online dot.
  final bool online;

  /// The colour behind the avatar, used for the gap around the online dot
  /// and inside a ring.
  final Color surround;

  /// A ring 3 px outside the avatar: green while speaking, accent when
  /// selected.
  final Color? ringColor;
  final double ringWidth;

  /// Draws the 3 px gap in [surround] even without a ring, to lift the
  /// avatar off whatever is behind it.
  final bool gap;

  @override
  Widget build(BuildContext context) {
    final corner = square ? (size / 3).roundToDouble() : size / 2;
    final face = CustomPaint(
      painter: _FacePainter(
        color: tone.background,
        corner: corner,
        gapColor: gap || ringColor != null ? surround : null,
        ringColor: ringColor,
        ringWidth: ringWidth,
      ),
      child: photo != null && icon == null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(corner),
              child: Image.memory(
                photo!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
                // A picture that cannot be read shows the letters.
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    label,
                    textScaler: TextScaler.noScaling,
                    style: AppText.base.copyWith(
                      color: tone.foreground,
                      fontWeight: fontWeight,
                      fontSize: fontSize ?? (size * 0.4).roundToDouble(),
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: icon != null
                  ? AppIcon(
                      icon!,
                      size: iconSize ?? (size * 0.46).roundToDouble(),
                      color: tone.foreground,
                    )
                  : Text(
                      label,
                      textScaler: TextScaler.noScaling,
                      style: AppText.base.copyWith(
                        color: tone.foreground,
                        fontWeight: fontWeight,
                        fontSize: fontSize ?? (size * 0.4).roundToDouble(),
                      ),
                    ),
            ),
    );

    final dot = size >= 44 ? 14.0 : 12.0;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            face,
            if (online)
              Positioned(
                right: -2,
                bottom: -2,
                width: dot,
                height: dot,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: surround, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Paints the avatar's shape, and around it the 3 px gap and the ring. Each
/// is the same shape grown outwards, so its corners grow with it. A box
/// shadow would keep the inner corner radius and look pinched.
class _FacePainter extends CustomPainter {
  const _FacePainter({
    required this.color,
    required this.corner,
    required this.gapColor,
    required this.ringColor,
    required this.ringWidth,
  });

  final Color color;
  final double corner;
  final Color? gapColor;
  final Color? ringColor;
  final double ringWidth;

  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    void shape(double grow, Color fill) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(grow),
        Radius.circular(corner + grow),
      ),
      Paint()..color = fill,
    );
    if (ringColor != null) shape(_gap + ringWidth, ringColor!);
    if (gapColor != null) shape(_gap, gapColor!);
    shape(0, color);
  }

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.color != color ||
      old.corner != corner ||
      old.gapColor != gapColor ||
      old.ringColor != ringColor ||
      old.ringWidth != ringWidth;
}
