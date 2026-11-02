import '../settings/app_settings.dart';
import 'detection_result.dart';

/// Removes unreliable detections before they reach the tracker.
///
/// Rules (CLAUDE.md): drop results below
/// [AppSettings.confidenceThreshold]; an object counts as confirmed only
/// after appearing in [AppSettings.confirmationHits] of the last
/// [AppSettings.confirmationWindow] results.
///
/// Implemented and unit-tested in Phase 3.
class DetectionFilter {
  DetectionFilter({required this.settings});

  final AppSettings settings;

  /// Feeds one frame's detections; returns those currently confirmed.
  List<DetectionResult> update(List<DetectionResult> detections) {
    throw UnimplementedError('DetectionFilter.update — Phase 3');
  }

  /// Clears the history (e.g. after pause/resume).
  void reset() {}
}
