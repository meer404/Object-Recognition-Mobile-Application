/// Measurements for one processed frame. One CSV row each.
class FrameMetrics {
  const FrameMetrics({
    required this.timestamp,
    required this.preprocessingMs,
    required this.inferenceMs,
    required this.postprocessingMs,
    required this.detectionCount,
    this.frameToSpeechStartMs,
  });

  final DateTime timestamp;
  final double preprocessingMs;
  final double inferenceMs;
  final double postprocessingMs;
  final int detectionCount;

  /// Null when the frame produced no speech.
  final double? frameToSpeechStartMs;
}

/// Periodic device-level sample (RAM, battery).
class DeviceSample {
  const DeviceSample({
    required this.timestamp,
    required this.ramMb,
    required this.batteryPercent,
  });

  final DateTime timestamp;
  final double ramMb;
  final int batteryPercent;
}

/// Records per-frame latency and periodic device metrics, exported as CSV to
/// the app documents directory. Analysis reports median and P95, not just
/// means (tools/analyze_metrics.py).
///
/// Implemented in Phase 4.
abstract class MetricsLogger {
  void logFrame(FrameMetrics metrics);
  void logDevice(DeviceSample sample);

  /// Writes buffered rows to CSV and returns the file path.
  Future<String> exportCsv();
}
