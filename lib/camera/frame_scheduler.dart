import '../settings/app_settings.dart';
import 'camera_frame.dart';

/// Signature of the work the scheduler runs for an accepted frame.
typedef FrameHandler = Future<void> Function(CameraFrame frame);

/// Decides which camera frames reach the detector.
///
/// Rules (CLAUDE.md):
/// - Run at most [AppSettings.targetInferencesPerSecond] inferences/sec.
/// - If an inference is still running, DROP the new frame. Never queue.
///
/// Implemented and unit-tested in Phase 2.
class FrameScheduler {
  FrameScheduler({required this.settings, required this.onFrame});

  final AppSettings settings;
  final FrameHandler onFrame;

  /// Offers a frame. It is either processed now or dropped.
  ///
  /// Returns true if the frame was accepted.
  bool offer(CameraFrame frame) {
    throw UnimplementedError('FrameScheduler.offer — Phase 2');
  }
}
