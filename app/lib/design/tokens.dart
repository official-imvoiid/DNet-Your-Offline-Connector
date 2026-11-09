import 'package:flutter/widgets.dart';

/// Colours from section 3 of the design spec, plus the few extra values the
/// reference HTML uses inside chat bubbles and polls.
abstract final class AppColors {
  static const bg = Color(0xFF1C1D22);
  static const surface = Color(0xFF24252B);
  static const raised = Color(0xFF2D2F36);
  static const selected = Color(0xFF34363E);
  static const line = Color(0xFF383A42);
  static const text = Color(0xFFF2F3F5);
  static const text2 = Color(0xFFB3B6C0);
  static const text3 = Color(0xFF8E919C);
  static const accent = Color(0xFF4DA3FF);
  static const accentInk = Color(0xFF0B1A2B);
  static const accentSoft = Color(0xFF1E2F45);
  static const ownBubble = Color(0xFF244B78);
  static const green = Color(0xFF3DD68C);
  static const greenInk = Color(0xFF0B2A1C);
  static const greenSoft = Color(0xFF1B3A2C);
  static const amber = Color(0xFFF5C451);
  static const amberSoft = Color(0xFF3D3218);
  static const red = Color(0xFFFF6B6B);
  static const redInk = Color(0xFF2B0F10);
  static const switchOff = Color(0xFF4A4D57);
  static const white = Color(0xFFFFFFFF);

  /// Time and "Gone in" text on the user's own bubbles.
  static const ownBubbleMeta = Color(0xFFC9DCF2);

  /// Read ticks on the user's own bubbles.
  static const ownBubbleTick = Color(0xFF9CCBFF);

  /// The fill of a poll option the user did not pick.
  static const pollBar = Color(0xFF3A3C44);
}

/// The eight avatar colour pairs. Each person and space keeps one everywhere.
enum AvatarTone {
  rose(Color(0xFF6B2F45), Color(0xFFFFD3E0)),
  blue(Color(0xFF2B4E7A), Color(0xFFCFE4FF)),
  violet(Color(0xFF4A3B78), Color(0xFFE0D6FF)),
  amber(Color(0xFF6A5216), Color(0xFFFFE9A8)),
  teal(Color(0xFF1D5560), Color(0xFFC5F1F7)),
  green(Color(0xFF1F5A45), Color(0xFFC9F5DF)),
  red(Color(0xFF5A2A2A), Color(0xFFFFD6D6)),
  grey(Color(0xFF3A3C44), Color(0xFFF2F3F5));

  const AvatarTone(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

/// The colour for someone's picture, worked out from their key. The same
/// person gets the same colour on every device, with nothing to send.
AvatarTone toneForKey(String keyHex) {
  const tones = [
    AvatarTone.rose,
    AvatarTone.blue,
    AvatarTone.violet,
    AvatarTone.amber,
    AvatarTone.teal,
    AvatarTone.green,
    AvatarTone.red,
  ];
  final first = keyHex.length >= 2
      ? int.tryParse(keyHex.substring(0, 2), radix: 16) ?? 0
      : 0;
  return tones[first % tones.length];
}

abstract final class AppFonts {
  static const sans = 'Figtree';
  static const mono = 'JetBrains Mono';

  /// Emoji, drawn by the font the app comes with rather than the device's.
  static const emoji = 'Noto Color Emoji';
}

/// Text styles. Sizes are in logical pixels and match the reference HTML.
abstract final class AppText {
  /// Base text: 15 px, line height 1.4. Everything else derives from this.
  static const base = TextStyle(
    fontFamily: AppFonts.sans,
    // Any emoji in the text.
    fontFamilyFallback: [AppFonts.emoji],
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: AppColors.text,
    // Stated, not left to inherit: Material text fields merge their theme's
    // style underneath this one, and that theme adds letter spacing.
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );

  /// Title on a tab screen: 28 px, weight 800.
  static final screenTitle = base.copyWith(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.28,
  );

  /// Title in a top bar: 18 px, weight 700.
  static final barTitle = base.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  /// Row title: 16 px, weight 700.
  static final rowTitle = base.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// Bold text at the base size.
  static final strong = base.copyWith(fontWeight: FontWeight.w700);

  /// Row detail: 13 px in the secondary colour.
  static final detail = base.copyWith(fontSize: 13, color: AppColors.text2);

  /// Row detail at 14 px.
  static final detail14 = base.copyWith(fontSize: 14, color: AppColors.text2);

  /// Section label: 13 px, weight 600, secondary colour.
  static final sectionLabel = base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.text2,
  );

  /// Timestamp: 12 px, tertiary colour.
  static final timestamp = base.copyWith(fontSize: 12, color: AppColors.text3);

  /// Footnote: 13 px, tertiary colour.
  static final footnote = base.copyWith(fontSize: 13, color: AppColors.text3);

  /// Codes, fingerprints, verification words and transfer speed.
  static TextStyle mono(double size, {Color color = AppColors.text}) =>
      base.copyWith(
        fontFamily: AppFonts.mono,
        fontWeight: FontWeight.w500,
        fontSize: size,
        color: color,
      );
}

/// Corner radii from the design spec.
abstract final class AppRadius {
  static const chip = 8.0;
  static const channelRow = 10.0;
  static const smallButton = 12.0;
  static const largeButton = 14.0;
  static const card = 16.0;
  static const hero = 20.0;
  static const sheet = 28.0;
}

/// The smallest touch target the design allows.
const double kMinTouchTarget = 44;
