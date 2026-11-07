import 'dart:typed_data';

import '../camera/camera_frame.dart';
import '../settings/app_settings.dart';
import 'model_runner.dart';
import 'object_detector.dart';
import 'postprocessing.dart';
import 'preprocessing.dart';

/// The whole detector for one frame, timed per stage. Synchronous: it runs
/// inside the detector's worker isolate.
class DetectionEngine {
  DetectionEngine({
    required ModelRunner runner,
    required AppSettings settings,
    required Set<int> allowedClasses,
  }) : _runner = runner,
       _settings = settings,
       _allowedClasses = allowedClasses;

  final ModelRunner _runner;
  final AppSettings _settings;
  final Set<int> _allowedClasses;
  Float32List? _input;

  DetectionOutput process(CameraFrame frame) {
    final int width = uprightWidth(frame);
    final int height = uprightHeight(frame);
    final LetterboxGeometry geometry = LetterboxGeometry.forImage(
      width: width,
      height: height,
      inputSize: _settings.modelInputSize,
    );

    final Stopwatch watch = Stopwatch()..start();
    final Float32List input = preprocessFrame(frame, geometry, output: _input);
    _input = input;
    final double preprocessingMs = _lapMs(watch);

    final Float32List raw = _runner.run(input);
    final double inferenceMs = _lapMs(watch);

    final detections = decodeDetections(
      raw,
      channels: _runner.channels,
      anchors: _runner.anchors,
      geometry: geometry,
      settings: _settings,
      allowedClasses: _allowedClasses,
    );
    final double postprocessingMs = _lapMs(watch);

    return DetectionOutput(
      detections: detections,
      imageWidth: width,
      imageHeight: height,
      timings: DetectionTimings(
        preprocessingMs: preprocessingMs,
        inferenceMs: inferenceMs,
        postprocessingMs: postprocessingMs,
      ),
    );
  }

  static double _lapMs(Stopwatch watch) {
    final double ms = watch.elapsedMicroseconds / 1000;
    watch.reset();
    return ms;
  }
}
