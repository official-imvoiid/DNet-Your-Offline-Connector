import '../design/app_icon.dart';

/// Icons for call controls the design kit does not draw: the sound and the
/// camera switched off. Same 24 unit grid and round-capped outline as the
/// kit's own speaker and camera.
abstract final class CallIcons {
  static const soundOff = AppIconData([
    IconPath('M4 9v6h4l5 4V5L8 9H4ZM17 9l4 6M21 9l-4 6'),
  ]);

  static const cameraOff = AppIconData([
    IconRect(3, 6, 13, 12, rx: 2),
    IconPath('m16 10 5-3v10l-5-3M3 3l18 18'),
  ]);

  /// A screen on a stand: sharing the screen.
  static const screen = AppIconData([
    IconRect(3, 4, 18, 12, rx: 2),
    IconPath('M8 20h8M12 16v4'),
  ]);

  /// Four corners pulled out: show a shared screen bigger.
  static const enlarge = AppIconData([
    IconPath('M14 4h6v6M10 20H4v-6M20 4l-6 6M4 20l6-6'),
  ]);

  /// Four corners pushed in: back to the smaller view.
  static const shrink = AppIconData([
    IconPath('M20 10h-6V4M4 14h6v6M14 10l6-6M10 14l-6 6'),
  ]);
}
