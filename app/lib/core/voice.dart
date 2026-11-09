/// The microphone and the speaker, for voice messages. Each kind of device
/// has its own; a device with neither has none, and the app then says
/// voice messages are not built there.
///
/// A recording is an ordinary sound file. It is sent like any other file,
/// sealed to the person it is for.
abstract class Voice {
  /// Starts recording into the file at [path]. False if the microphone
  /// cannot be used, which is nearly always because the user has not
  /// allowed it.
  Future<bool> start(String path);

  /// Stops, keeping what was recorded. False if there is nothing to keep.
  Future<bool> stop();

  /// Stops and throws away what was recorded.
  Future<void> cancel();

  /// Plays the sound file at [path] from its start. False if it cannot be
  /// played.
  Future<bool> play(String path);

  Future<void> stopPlaying();
}
