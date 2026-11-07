import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/metrics/evaluation_recorder.dart';
import 'package:kurdish_vision/metrics/metrics_logger.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

class _FakeLogger implements MetricsLogger {
  Object? startError;

  final List<FrameMetrics> frames = <FrameMetrics>[];
  final List<DeviceSample> samples = <DeviceSample>[];
  int starts = 0;
  int stops = 0;
  int flushes = 0;
  bool active = false;

  @override
  bool get isActive => active;

  @override
  Future<String> start(SessionInfo info) async {
    final Object? error = startError;
    startError = null;
    if (error != null) throw error;
    starts++;
    active = true;
    return 'session-$starts';
  }

  @override
  void logFrame(FrameMetrics metrics) {
    if (active) frames.add(metrics);
  }

  @override
  void logDevice(DeviceSample sample) {
    if (active) samples.add(sample);
  }

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<List<String>> stop() async {
    stops++;
    active = false;
    return <String>['a', 'b', 'c'];
  }

  @override
  Future<List<String>> latestSessionFiles() async => <String>['latest'];
}

class _FakeProbe implements DeviceProbe {
  int rss = 200 * 1024 * 1024;
  Object? batteryError;

  @override
  int rssBytes() => rss;

  @override
  Future<int?> batteryPercent() async {
    if (batteryError != null) throw batteryError!;
    return 80;
  }

  @override
  Future<String> batteryState() async => 'discharging';
}

SessionInfo _info() => SessionInfo(
  startedAt: DateTime.utc(2026),
  buildMode: 'profile',
  appVersion: '1',
  gitCommit: 'x',
  device: 'd',
  os: 'o',
  accelerator: 'a',
  modelAsset: 'm',
  modelBytes: 1,
  settings: const <String, Object?>{},
);

void main() {
  const AppSettings off = AppSettings();
  final AppSettings on = off.copyWith(
    evaluationMode: true,
    // Long, so the timer never fires during a test.
    deviceSampleInterval: const Duration(hours: 1),
  );

  late _FakeLogger logger;
  late _FakeProbe probe;
  late SchedulerCounts counts;
  late Duration clock;
  late EvaluationRecorder recorder;

  setUp(() {
    logger = _FakeLogger();
    probe = _FakeProbe();
    counts = const SchedulerCounts(accepted: 0, droppedBusy: 0, droppedRate: 0);
    clock = Duration.zero;
    recorder = EvaluationRecorder(
      logger: logger,
      probe: probe,
      sessionInfo: () async => _info(),
      counts: () => counts,
      now: () => DateTime.utc(2026),
      clock: () => clock,
    );
  });

  tearDown(() => recorder.dispose());

  test('evaluation mode off: no session, nothing recorded', () async {
    await recorder.apply(off);
    recorder.logFrame(
      FrameMetrics(
        timestamp: DateTime.utc(2026),
        preprocessingMs: 1,
        inferenceMs: 1,
        postprocessingMs: 1,
        detectionCount: 0,
      ),
    );
    expect(logger.starts, 0);
    expect(logger.frames, isEmpty);
    expect(recorder.isRecording, isFalse);
  });

  test('turning it on starts one session; repeating changes nothing', () async {
    await recorder.apply(on);
    await recorder.apply(on);
    expect(logger.starts, 1);
    expect(recorder.isRecording, isTrue);
  });

  test('turning it off stops the session with a final sample', () async {
    await recorder.apply(on);
    final int before = logger.samples.length;
    await recorder.apply(off);
    expect(logger.stops, 1);
    expect(logger.samples.length, before + 1);
    expect(recorder.isRecording, isFalse);
  });

  test('the first sample has no rates; later ones are per second', () async {
    // Frames dropped before the session must not show up in it. On the phone,
    // the first row reported drops since the app started (42 and 108).
    counts = const SchedulerCounts(
      accepted: 10,
      droppedBusy: 42,
      droppedRate: 108,
    );
    await recorder.apply(on);
    final DeviceSample first = logger.samples.single;
    expect(first.cameraFps, isNull);
    expect(first.inferenceFps, isNull);
    expect(first.droppedBusy, isNull, reason: 'baseline, not app lifetime');
    expect(first.droppedRate, isNull);
    expect(first.rssMb, closeTo(200, 1e-9));
    expect(first.batteryPercent, 80);

    // 10 s later: 300 more frames arrived, 38 inferred, 2 dropped busy, 260 by
    // rate.
    clock = const Duration(seconds: 10);
    counts = const SchedulerCounts(
      accepted: 48,
      droppedBusy: 44,
      droppedRate: 368,
    );
    await recorder.sample();
    final DeviceSample second = logger.samples.last;
    expect(second.cameraFps, closeTo(30, 1e-9));
    expect(second.inferenceFps, closeTo(3.8, 1e-9));
    expect(second.droppedBusy, 2);
    expect(second.droppedRate, 260);
  });

  test('rates and drops are per interval, not cumulative', () async {
    await recorder.apply(on);
    clock = const Duration(seconds: 10);
    counts = const SchedulerCounts(
      accepted: 40,
      droppedBusy: 5,
      droppedRate: 255,
    );
    await recorder.sample();
    clock = const Duration(seconds: 20);
    counts = const SchedulerCounts(
      accepted: 70,
      droppedBusy: 6,
      droppedRate: 525,
    );
    await recorder.sample();
    expect(logger.samples.last.inferenceFps, closeTo(3, 1e-9));
    expect(logger.samples.last.droppedBusy, 1);
    expect(logger.samples.last.droppedRate, 270);
  });

  test('a new session starts its rates from scratch', () async {
    await recorder.apply(on);
    counts = const SchedulerCounts(
      accepted: 40,
      droppedBusy: 0,
      droppedRate: 0,
    );
    await recorder.apply(off);
    await recorder.apply(on);
    expect(logger.samples.last.inferenceFps, isNull);
  });

  test('a battery failure is recorded as unknown, not a crash', () async {
    probe.batteryError = StateError('no battery API');
    await recorder.apply(on);
    expect(logger.samples.single.batteryPercent, isNull);
    expect(logger.samples.single.batteryState, 'unknown');
  });

  test('a session that fails to start can be retried', () async {
    logger.startError = const FileSystemException('no documents dir');
    await recorder.apply(on); // Must not throw.
    expect(recorder.isRecording, isFalse);

    await recorder.apply(off);
    await recorder.apply(on);
    expect(recorder.isRecording, isTrue, reason: 'the switch still works');
  });

  test('frames are forwarded while recording', () async {
    await recorder.apply(on);
    recorder.logFrame(
      FrameMetrics(
        timestamp: DateTime.utc(2026),
        preprocessingMs: 1,
        inferenceMs: 1,
        postprocessingMs: 1,
        detectionCount: 0,
      ),
    );
    expect(logger.frames, hasLength(1));
  });

  test('flush, export and dispose reach the logger', () async {
    await recorder.apply(on);
    await recorder.flush();
    expect(logger.flushes, 1);
    expect(await recorder.exportFiles(), <String>['latest']);
    await recorder.dispose();
    expect(logger.stops, 1);
  });

  test('samples itself on the configured interval', () async {
    await recorder.apply(
      off.copyWith(
        evaluationMode: true,
        deviceSampleInterval: const Duration(milliseconds: 20),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(logger.samples.length, greaterThan(2));
  });
}
