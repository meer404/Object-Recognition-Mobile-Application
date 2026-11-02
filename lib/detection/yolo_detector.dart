import '../camera/camera_frame.dart';
import 'object_detector.dart';

/// YOLO (nano/small) implementation of [ObjectDetector].
///
/// Phase 3: YUV/BGRA → RGB conversion, letterbox resize, inference in a
/// background isolate, NMS, mapping to normalized DetectionResults.
/// Android tries the GPU delegate first and falls back to CPU/XNNPACK.
/// The plugin choice (Ultralytics vs tflite_flutter) is made in Phase 1;
/// see docs/decisions.md.
class YoloDetector implements ObjectDetector {
  @override
  bool get isLoaded => false;

  @override
  Future<void> load() {
    throw UnimplementedError('YoloDetector.load — Phase 3');
  }

  @override
  Future<DetectionOutput> detect(CameraFrame frame) {
    throw UnimplementedError('YoloDetector.detect — Phase 3');
  }

  @override
  Future<void> dispose() async {}
}
