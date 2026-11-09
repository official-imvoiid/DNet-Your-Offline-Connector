import 'app_icon.dart';

/// Icons the design kit does not have, for controls it does not draw:
/// sending, editing, deleting, settings and roles. They are on the same
/// 24 unit grid and drawn as the same round-capped outline, so they sit
/// beside the kit's own without looking different.
abstract final class ExtraIcons {
  static const send = AppIconData([IconPath('M4 12 20 4l-6 17-3-7-7-2Z')]);

  static const edit = AppIconData([
    IconPath('M4 20h4L19 9l-4-4L4 16v4Z'),
    IconPath('m13 7 4 4'),
  ]);

  static const trash = AppIconData([
    IconPath('M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13'),
  ]);

  static const settings = AppIconData([
    IconPath('M4 7h8M18 7h2M4 17h2M12 17h8'),
    IconCircle(15, 7, 2.5),
    IconCircle(9, 17, 2.5),
  ]);

  static const shield = AppIconData([
    IconPath('M12 3 5 6v6l2 5 5 4 5-4 2-5V6l-7-3Z'),
  ]);

  /// The emoji and sticker panel.
  static const smile = AppIconData([
    IconCircle(12, 12, 9),
    IconPath('M8.5 14.5a4.5 4.5 0 0 0 7 0'),
    IconCircle(9, 9.5, 1, filled: true),
    IconCircle(15, 9.5, 1, filled: true),
  ]);

  /// Back to typing, from the emoji panel.
  static const keyboard = AppIconData([
    IconRect(3, 6, 18, 12, rx: 2),
    IconPath('M7 10h.01M11 10h.01M15 10h.01M8 14h8'),
  ]);

  /// Full screen.
  static const expand = AppIconData([
    IconPath('M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5'),
  ]);

  /// A sticker: a square with a corner peeling up.
  static const sticker = AppIconData([
    IconPath('M14 20H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8l-6 6Z'),
    IconPath('M14 20v-4a2 2 0 0 1 2-2h4'),
  ]);
}
