import '../detection/detection_result.dart';
import '../settings/app_settings.dart';
import 'speech_service.dart';

/// Builds natural Sorani sentences from objects to announce.
///
/// At most [AppSettings.maxObjectsPerSentence] objects, ordered by
/// [DetectionResult.priority] (closest/largest first). Template example:
/// «لەبەردەمت مێزێک هەیە. پەرداخێک و کورسییەکیش دەبینرێن.»
///
/// Implemented and unit-tested in Phase 3.
class PhraseBuilder {
  PhraseBuilder({required this.settings});

  final AppSettings settings;

  SpeechRequest build(List<DetectionResult> objects) {
    throw UnimplementedError('PhraseBuilder.build — Phase 3');
  }
}
