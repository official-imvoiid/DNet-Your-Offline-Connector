import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

/// The app pauses videos itself when it is put away, so the player is
/// told not to watch for that.
final videoOptions = VideoPlayerOptions(allowBackgroundPlayback: true);

/// How long the video at [path] runs, in seconds, as this device's player
/// reads it. Zero if it cannot read it.
Future<int> probeVideoSeconds(String path) async {
  final controller = VideoPlayerController.file(
    File(path),
    videoPlayerOptions: videoOptions,
  );
  final ready = controller.initialize();
  try {
    await ready.timeout(const Duration(seconds: 8));
  } on Object {
    // Not a video this device plays, or too slow to tell. A player that
    // never started is not stopped: there is nothing to stop.
    unawaited(ready.then((_) => controller.dispose(), onError: (_) {}));
    return 0;
  }
  final seconds = controller.value.duration.inSeconds;
  await controller.dispose();
  return seconds;
}
