/// Low-level audio player for a sequence of asset clips.
///
/// This thin seam lets AudioClipSpeech's logic be unit-tested without a
/// device. The real implementation is JustAudioClipPlayer.
abstract class ClipPlayer {
  /// Configures the audio session (ducking). Call once.
  Future<void> init();

  /// Plays [assetPaths] back to back. Calls [onStarted] when audio begins.
  /// Completes when playback finishes or [stop] is called.
  Future<void> playSequence(
    List<String> assetPaths, {
    required void Function() onStarted,
  });

  /// Stops playback. A pending [playSequence] completes.
  Future<void> stop();

  /// Output volume, 0–1.
  Future<void> setVolume(double volume);

  Future<void> dispose();
}
