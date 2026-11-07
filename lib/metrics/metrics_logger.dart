import 'dart:convert';

/// Measurements for one processed frame. One row of `frames.csv`.
class FrameMetrics {
  const FrameMetrics({
    required this.timestamp,
    required this.preprocessingMs,
    required this.inferenceMs,
    required this.postprocessingMs,
    required this.detectionCount,
    this.frameToSpeechStartMs,
  });

  /// When the camera delivered the frame.
  final DateTime timestamp;
  final double preprocessingMs;
  final double inferenceMs;
  final double postprocessingMs;
  final int detectionCount;

  /// From frame arrival to speech starting. Null when the frame produced no
  /// speech.
  final double? frameToSpeechStartMs;

  /// Time inside the detector. Excludes the wait for a free worker.
  double get totalMs => preprocessingMs + inferenceMs + postprocessingMs;
}

/// A periodic device-level sample. One row of `device.csv`.
class DeviceSample {
  const DeviceSample({
    required this.timestamp,
    required this.rssMb,
    required this.batteryPercent,
    required this.batteryState,
    required this.cameraFps,
    required this.inferenceFps,
    required this.droppedBusy,
    required this.droppedRate,
  });

  final DateTime timestamp;

  /// Resident memory of the whole app process, in MiB.
  final double rssMb;

  /// Null when the platform could not report it.
  final int? batteryPercent;

  /// `charging`, `discharging`, `full`, `connectedNotCharging` or `unknown`.
  final String batteryState;

  /// Frames per second over the interval since the previous sample. Null for
  /// the first sample of a session.
  final double? cameraFps;
  final double? inferenceFps;

  /// Frames dropped during that interval, by reason.
  final int droppedBusy;
  final int droppedRate;
}

/// What a measurement session ran on. Written once as `session.json`.
class SessionInfo {
  const SessionInfo({
    required this.startedAt,
    required this.buildMode,
    required this.appVersion,
    required this.gitCommit,
    required this.device,
    required this.os,
    required this.accelerator,
    required this.modelAsset,
    required this.modelBytes,
    required this.settings,
  });

  final DateTime startedAt;

  /// `debug`, `profile` or `release`. Only profile and release numbers are
  /// valid for performance claims (D-021).
  final String buildMode;
  final String appVersion;
  final String gitCommit;
  final String device;
  final String os;
  final String accelerator;
  final String modelAsset;
  final int? modelBytes;
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => <String, Object?>{
    'started_utc': startedAt.toUtc().toIso8601String(),
    'build_mode': buildMode,
    'valid_for_performance_claims': buildMode != 'debug',
    'app_version': appVersion,
    'git_commit': gitCommit,
    'device': device,
    'os': os,
    'accelerator': accelerator,
    'model_asset': modelAsset,
    'model_bytes': modelBytes,
    'settings': settings,
  };

  String toPrettyJson() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

/// Records evaluation sessions: per-frame latency and periodic device metrics.
/// Nothing is recorded outside a session. Analysis reports median and P95, not
/// just means (tools/analyze_metrics.py).
abstract class MetricsLogger {
  bool get isActive;

  /// Starts a new session and returns its folder. Ends any running session.
  Future<String> start(SessionInfo info);

  void logFrame(FrameMetrics metrics);
  void logDevice(DeviceSample sample);

  /// Writes buffered rows to disk.
  Future<void> flush();

  /// Ends the session, writing everything. Returns its files.
  Future<List<String>> stop();

  /// Files of the running or most recent session, flushed, or empty if there
  /// has never been one.
  Future<List<String>> latestSessionFiles();
}

const String frameCsvHeader =
    'timestamp_utc,preprocess_ms,inference_ms,postprocess_ms,total_ms,'
    'detections,frame_to_speech_start_ms';

const String deviceCsvHeader =
    'timestamp_utc,rss_mb,battery_percent,battery_state,camera_fps,'
    'inference_fps,dropped_busy,dropped_rate';

String frameCsvRow(FrameMetrics m) => <String>[
  _time(m.timestamp),
  _number(m.preprocessingMs, 3),
  _number(m.inferenceMs, 3),
  _number(m.postprocessingMs, 3),
  _number(m.totalMs, 3),
  '${m.detectionCount}',
  _number(m.frameToSpeechStartMs, 3),
].join(',');

String deviceCsvRow(DeviceSample s) => <String>[
  _time(s.timestamp),
  _number(s.rssMb, 1),
  s.batteryPercent?.toString() ?? '',
  csvField(s.batteryState),
  _number(s.cameraFps, 2),
  _number(s.inferenceFps, 2),
  '${s.droppedBusy}',
  '${s.droppedRate}',
].join(',');

/// Quotes a CSV field if needed (RFC 4180).
String csvField(String value) {
  if (!value.contains(RegExp('[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String _time(DateTime t) => t.toUtc().toIso8601String();

String _number(double? value, int decimals) =>
    value == null || !value.isFinite ? '' : value.toStringAsFixed(decimals);
