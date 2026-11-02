import 'speech_service.dart';

/// OPTIONAL speech path via system TTS (`flutter_tts`).
///
/// Used only if a Sorani (ckb) voice is verified on the device at runtime.
/// Most devices are expected NOT to have one. Implemented in Phase 1A.
class TtsSpeech implements SpeechService {
  @override
  Future<void> init() {
    throw UnimplementedError('TtsSpeech.init — Phase 1A');
  }

  /// Unverified until Phase 1A probes the device's voices.
  @override
  Future<bool> get supportsSorani async => false;

  @override
  Future<void> speak(SpeechRequest request) {
    throw UnimplementedError('TtsSpeech.speak — Phase 1A');
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<bool> get isSpeaking => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}
}
