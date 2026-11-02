import 'speech_service.dart';

/// PRIMARY speech path: plays pre-recorded Sorani clips from assets/audio/
/// (`<class_id>.m4a` plus phrase fragments), concatenated in order.
///
/// Implemented in Phase 1A.
class AudioClipSpeech implements SpeechService {
  @override
  Future<void> init() {
    throw UnimplementedError('AudioClipSpeech.init — Phase 1A');
  }

  @override
  Future<bool> get supportsSorani async => true;

  @override
  Future<void> speak(SpeechRequest request) {
    throw UnimplementedError('AudioClipSpeech.speak — Phase 1A');
  }

  @override
  Future<void> stop() async {}

  @override
  Stream<bool> get isSpeaking => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}
}
