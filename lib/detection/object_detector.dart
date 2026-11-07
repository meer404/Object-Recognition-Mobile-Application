import '../camera/camera_frame.dart';
import 'detection_result.dart';

/// Per-stage timings of one [ObjectDetector.detect] call, in milliseconds.
class DetectionTimings {
  const DetectionTimings({
    required this.preprocessingMs,
    required this.inferenceMs,
    required this.postprocessingMs,
  });

  final double preprocessingMs;
  final double inferenceMs;
  final double postprocessingMs;
}

/// Output of one detector run: detections plus measured stage timings.
class DetectionOutput {
  const DetectionOutput({
    required this.detections,
    required this.timings,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<DetectionResult> detections;
  final DetectionTimings timings;

  /// Size of the upright image the normalized boxes refer to.
  final int imageWidth;
  final int imageHeight;
}

/// On-device object detector.
///
/// Platform-specific inference is an implementation detail behind this
/// interface. Implementations must not block the UI isolate: preprocessing and
/// inference run in a background isolate or a native thread.
abstract class ObjectDetector {
  /// Loads the model and allocates resources. Call once before [detect].
  /// Throws if the model cannot be used.
  Future<void> load();

  /// Whether [load] has completed successfully.
  bool get isLoaded;

  /// Runs preprocessing, inference and NMS on [frame]. The returned future
  /// always completes: it fails rather than hangs if the detector dies.
  ///
  /// Returned detections are NOT yet confidence-filtered for speech; that is
  /// the job of the DetectionFilter.
  Future<DetectionOutput> detect(CameraFrame frame);

  /// Releases the model, isolates and delegates.
  Future<void> dispose();
}
