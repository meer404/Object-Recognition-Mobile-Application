/// What to say, in both forms supported by the speech back-ends.
class SpeechRequest {
  const SpeechRequest({required this.text, required this.clipKeys});

  /// Full Sorani sentence (used by TTS and for logging).
  final String text;

  /// Ordered audio fragment keys under assets/audio/ (used by clip playback).
  final List<String> clipKeys;
}

/// Speech output abstraction.
///
/// Rules: new speech never overlaps old speech. A new request either waits
/// or replaces the current one, but two utterances never play at once.
/// Output should duck, not mask, environmental sound.
abstract class SpeechService {
  /// Prepares the audio session / engine.
  Future<void> init();

  /// Whether this back-end can actually speak Sorani on this device.
  /// Never assume true for TTS; it must be verified at runtime.
  Future<bool> get supportsSorani;

  /// Speaks [request]. The future completes when playback STARTS, so the
  /// frame-to-speech-start latency can be measured.
  Future<void> speak(SpeechRequest request);

  /// Stops current speech immediately.
  Future<void> stop();

  /// Emits true while speaking and false when idle.
  Stream<bool> get isSpeaking;

  Future<void> dispose();
}
