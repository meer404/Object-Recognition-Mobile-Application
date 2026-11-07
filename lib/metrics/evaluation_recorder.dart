import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';
import 'metrics_logger.dart';

/// Frame counts from the FrameScheduler, used to compute rates.
class SchedulerCounts {
  const SchedulerCounts({
    required this.accepted,
    required this.droppedBusy,
    required this.droppedRate,
  });

  final int accepted;
  final int droppedBusy;
  final int droppedRate;

  /// Every frame the camera delivered.
  int get received => accepted + droppedBusy + droppedRate;
}

/// Device readings. Behind an interface so tests need no plugins.
abstract class DeviceProbe {
  /// Resident memory of the app process, in bytes.
  int rssBytes();

  /// Battery level 0–100, or null if unavailable.
  Future<int?> batteryPercent();

  /// Charging state name, or `unknown`.
  Future<String> batteryState();
}

/// Runs evaluation sessions: starts and stops them with
/// [AppSettings.evaluationMode], forwards frame metrics, and samples the device
/// every [AppSettings.deviceSampleInterval].
class EvaluationRecorder {
  EvaluationRecorder({
    required MetricsLogger logger,
    required DeviceProbe probe,
    required Future<SessionInfo> Function() sessionInfo,
    required SchedulerCounts Function() counts,
    DateTime Function()? now,
    Duration Function()? clock,
  }) : _logger = logger,
       _probe = probe,
       _sessionInfo = sessionInfo,
       _counts = counts,
       _now = now ?? DateTime.now,
       _clock = clock ?? _stopwatchClock();

  final MetricsLogger _logger;
  final DeviceProbe _probe;
  final Future<SessionInfo> Function() _sessionInfo;
  final SchedulerCounts Function() _counts;
  final DateTime Function() _now;
  final Duration Function() _clock;

  Timer? _timer;
  SchedulerCounts? _lastCounts;
  Duration? _lastAt;

  /// Start/stop requests run one at a time.
  Future<void> _queue = Future<void>.value();

  bool get isRecording => _logger.isActive;

  /// Starts or stops a session to match [settings].
  Future<void> apply(AppSettings settings) => _enqueue(() async {
    if (settings.evaluationMode && !_logger.isActive) {
      await _start(settings);
    } else if (!settings.evaluationMode && _logger.isActive) {
      await _stop();
    }
  });

  void logFrame(FrameMetrics metrics) => _logger.logFrame(metrics);

  /// Writes buffered rows, e.g. when the app is paused or backgrounded.
  Future<void> flush() => _logger.flush();

  /// Files to export: the running or most recent session.
  Future<List<String>> exportFiles() => _logger.latestSessionFiles();

  Future<void> dispose() => _enqueue(_stop);

  /// Runs [operation] after the queued ones. A failure (e.g. no documents
  /// directory) is logged and the queue carries on, so the switch keeps working.
  Future<void> _enqueue(Future<void> Function() operation) => _queue = _queue
      .then((_) => operation())
      .catchError((Object error, StackTrace stackTrace) {
        developer.log(
          'evaluation session failed',
          name: 'metrics',
          error: error,
          stackTrace: stackTrace,
        );
      });

  Future<void> _start(AppSettings settings) async {
    final String folder = await _logger.start(await _sessionInfo());
    developer.log('evaluation session started: $folder', name: 'metrics');
    _lastCounts = null;
    _lastAt = null;
    await sample();
    _timer = Timer.periodic(
      settings.deviceSampleInterval,
      (_) => unawaited(sample()),
    );
  }

  Future<void> _stop() async {
    if (!_logger.isActive) return;
    _timer?.cancel();
    _timer = null;
    await sample();
    await _logger.stop();
  }

  /// Takes one device sample now. Rates cover the time since the previous one.
  @visibleForTesting
  Future<void> sample() async {
    if (!_logger.isActive) return;
    final SchedulerCounts counts = _counts();
    final Duration at = _clock();
    final SchedulerCounts? previous = _lastCounts;
    final Duration? previousAt = _lastAt;
    _lastCounts = counts;
    _lastAt = at;

    double? perSecond(int delta) {
      if (previous == null || previousAt == null) return null;
      final double seconds = (at - previousAt).inMicroseconds / 1e6;
      return seconds > 0 ? delta / seconds : null;
    }

    int? battery;
    String state = 'unknown';
    try {
      battery = await _probe.batteryPercent();
      state = await _probe.batteryState();
    } catch (error) {
      developer.log('battery unavailable: $error', name: 'metrics');
    }

    _logger.logDevice(
      DeviceSample(
        timestamp: _now(),
        rssMb: _probe.rssBytes() / (1024 * 1024),
        batteryPercent: battery,
        batteryState: state,
        cameraFps: perSecond(counts.received - (previous?.received ?? 0)),
        inferenceFps: perSecond(counts.accepted - (previous?.accepted ?? 0)),
        // The first sample is the baseline: before it, drops belong to no
        // session (on the phone it reported drops since app start).
        droppedBusy: previous == null
            ? null
            : counts.droppedBusy - previous.droppedBusy,
        droppedRate: previous == null
            ? null
            : counts.droppedRate - previous.droppedRate,
      ),
    );
  }

  static Duration Function() _stopwatchClock() {
    final Stopwatch stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
