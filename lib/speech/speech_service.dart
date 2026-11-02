/// What happened to a [SpeechRequest].
enum SpeechOutcome {
  /// Playback started. The future completes at this moment.
  started,

  /// Replaced by a newer request, or stopped before it started.
  dropped,

  /// No playable content (e.g. all clips missing).
  nothingToSay,

  /// The back-end failed before playback started.
  failed,
}

/// What to say, in both forms supported by the speech back-ends.
class SpeechRequest {
  const SpeechRequest({
    required this.text,
    required this.clipKeys,
    this.interrupt = false,
  });

  /// Full Sorani sentence (used by TTS and for logging).
  final String text;

  /// Ordered audio clip keys from assets/audio/manifest.json.
  final List<String> clipKeys;

  /// If true, current speech is cut off and this request plays next
  /// (used for the user's Repeat gesture). If false, current speech
  /// finishes first.
  final bool interrupt;
}

/// Speech output abstraction.
///
/// Overlap rule (docs/decisions.md D-008): two utterances never play at
/// once. Current speech finishes; while it plays, only the NEWEST request
/// waits and older waiting requests are dropped. `interrupt: true` and
/// [stop] cut current speech off.
///
/// Output must duck, not mask, environmental sound.
abstract class SpeechService {
  /// Prepares the audio session or engine. Call once before [speak].
  Future<void> init();

  /// Whether this back-end can actually speak Sorani on this device.
  /// Never assume true for TTS; it must be verified at runtime.
  Future<bool> get supportsSorani;

  /// Submits [request]. Completes with [SpeechOutcome.started] when playback
  /// STARTS, so frame-to-speech-start latency can be measured. Completes
  /// with another outcome as soon as it is known the request will not play.
  Future<SpeechOutcome> speak(SpeechRequest request);

  /// Stops current speech immediately and drops any waiting request.
  Future<void> stop();

  /// Output volume, 0–1.
  Future<void> setVolume(double volume);

  /// Whether something is currently being spoken.
  bool get speaking;

  /// Emits true when speech starts and false when it becomes idle.
  Stream<bool> get isSpeaking;

  Future<void> dispose();
}
