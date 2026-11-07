import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/metrics/csv_metrics_logger.dart';
import 'package:kurdish_vision/metrics/metrics_logger.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

final DateTime _start = DateTime.utc(2026, 11, 8, 14, 30, 5);

SessionInfo _info() => SessionInfo(
  startedAt: _start,
  buildMode: 'profile',
  appVersion: '1.0.0+1',
  gitCommit: 'abc123',
  device: 'Test Phone',
  os: 'Android 15 (API 35)',
  accelerator: 'gpu (OpenGL/OpenCL)',
  modelAsset: 'assets/models/yolo26n_320_fp32.tflite',
  modelBytes: 9894796,
  settings: const AppSettings().toJson(),
);

/// Ten frames (every third with speech) and three device samples, all with
/// exact values, so the analyzer test can check its arithmetic.
void writeReferenceSession(MetricsLogger logger) {
  for (int i = 0; i < 10; i++) {
    logger.logFrame(
      FrameMetrics(
        timestamp: _start.add(Duration(milliseconds: 250 * i)),
        preprocessingMs: 5.0 + i,
        inferenceMs: 20.0 + 2 * i,
        postprocessingMs: 1.0,
        detectionCount: i % 4,
        frameToSpeechStartMs: i % 3 == 0 ? 100.0 + 10 * i : null,
      ),
    );
  }
  for (int i = 0; i < 3; i++) {
    logger.logDevice(
      DeviceSample(
        timestamp: _start.add(Duration(seconds: 10 * i)),
        rssMb: 300.0 + 5 * i,
        batteryPercent: 90 - i,
        batteryState: 'discharging',
        cameraFps: i == 0 ? null : 30.0,
        inferenceFps: i == 0 ? null : 3.5 + i * 0.25,
        droppedBusy: i,
        droppedRate: i == 0 ? 0 : 260,
      ),
    );
  }
}

void main() {
  late Directory root;
  late CsvMetricsLogger logger;

  setUp(() {
    root = Directory.systemTemp.createTempSync('metrics_test_');
    logger = CsvMetricsLogger(
      root: () async => root,
      flushInterval: const Duration(minutes: 1),
      now: () => _start,
    );
  });

  tearDown(() async {
    await logger.stop();
    root.deleteSync(recursive: true);
  });

  String read(String folder, String name) =>
      File('$folder${Platform.pathSeparator}$name').readAsStringSync();

  FrameMetrics frame(int ms) => FrameMetrics(
    timestamp: _start.add(Duration(milliseconds: ms)),
    preprocessingMs: 1,
    inferenceMs: 2,
    postprocessingMs: 3,
    detectionCount: 1,
  );

  test('nothing is written outside a session', () async {
    logger.logFrame(frame(0));
    await logger.flush();
    expect(Directory('${root.path}/metrics').existsSync(), isFalse);
    expect(await logger.latestSessionFiles(), isEmpty);
  });

  test('a session folder gets session.json and both CSV headers', () async {
    final String folder = await logger.start(_info());
    expect(folder, endsWith('20261108T143005Z'));
    expect(logger.isActive, isTrue);
    expect(read(folder, 'session.json'), _info().toPrettyJson());
    expect(read(folder, 'frames.csv'), '$frameCsvHeader\n');
    expect(read(folder, 'device.csv'), '$deviceCsvHeader\n');
  });

  test('rows are buffered until flushed', () async {
    final String folder = await logger.start(_info());
    logger.logFrame(frame(0));
    expect(read(folder, 'frames.csv'), '$frameCsvHeader\n');
    await logger.flush();
    expect(
      read(folder, 'frames.csv'),
      '$frameCsvHeader\n${frameCsvRow(frame(0))}\n',
    );
  });

  test('flushing twice appends without duplicating', () async {
    final String folder = await logger.start(_info());
    logger.logFrame(frame(0));
    await logger.flush();
    logger.logFrame(frame(250));
    await logger.flush();
    await logger.flush();
    expect(
      read(folder, 'frames.csv').trim().split('\n'),
      hasLength(3),
      reason: 'header + 2 rows',
    );
  });

  test('flushes on its own every interval', () async {
    final CsvMetricsLogger quick = CsvMetricsLogger(
      root: () async => root,
      flushInterval: const Duration(milliseconds: 20),
      now: () => _start.add(const Duration(hours: 1)),
    );
    final String folder = await quick.start(_info());
    quick.logFrame(frame(0));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(read(folder, 'frames.csv').trim().split('\n'), hasLength(2));
    await quick.stop();
  });

  test(
    'stop writes everything, ends the session and returns its files',
    () async {
      final String folder = await logger.start(_info());
      logger.logFrame(frame(0));
      final List<String> files = await logger.stop();
      expect(logger.isActive, isFalse);
      expect(
        files.map((String f) => f.split(Platform.pathSeparator).last),
        <String>['session.json', 'frames.csv', 'device.csv'],
      );
      expect(read(folder, 'frames.csv').trim().split('\n'), hasLength(2));

      logger.logFrame(frame(250));
      await logger.flush();
      expect(
        read(folder, 'frames.csv').trim().split('\n'),
        hasLength(2),
        reason: 'rows after stop are ignored',
      );
    },
  );

  test('a new session in the same second gets its own folder', () async {
    final String first = await logger.start(_info());
    final String second = await logger.start(_info());
    expect(second, isNot(first));
    expect(second, endsWith('20261108T143005Z-2'));
  });

  test('the latest session is found again after a restart', () async {
    await logger.start(_info());
    await logger.stop();
    final CsvMetricsLogger later = CsvMetricsLogger(
      root: () async => root,
      flushInterval: const Duration(minutes: 1),
    );
    final List<String> files = await later.latestSessionFiles();
    expect(files, hasLength(3));
    expect(files.first, contains('20261108T143005Z'));
    expect(File(files.first).existsSync(), isTrue);
  });

  test('exporting a running session flushes it first', () async {
    await logger.start(_info());
    logger.logFrame(frame(0));
    final List<String> files = await logger.latestSessionFiles();
    expect(File(files[1]).readAsStringSync().trim().split('\n'), hasLength(2));
  });

  test('sessionStamp sorts by time and is file-system safe', () {
    expect(sessionStamp(DateTime.utc(2026, 1, 2, 3, 4, 5)), '20260102T030405Z');
    expect(
      sessionStamp(
        DateTime.utc(2026, 1, 2, 3, 4, 5),
      ).compareTo(sessionStamp(DateTime.utc(2026, 1, 2, 3, 4, 6))),
      lessThan(0),
    );
  });

  group('reference session', () {
    // tools/test_analyze_metrics.py reads these exact files, so the Python
    // analyzer is tested against what the Dart logger really writes.
    // Regenerate with: flutter test --update-goldens test/metrics
    const String fixture = 'test/fixtures/metrics_session';

    test('matches the committed fixture', () async {
      final String folder = await logger.start(_info());
      writeReferenceSession(logger);
      await logger.stop();
      for (final String name in CsvMetricsLogger.files) {
        final File expected = File('$fixture/$name');
        final String actual = read(folder, name);
        if (autoUpdateGoldenFiles) {
          expected
            ..createSync(recursive: true)
            ..writeAsStringSync(actual);
        }
        expect(actual, expected.readAsStringSync(), reason: name);
      }
    });
  });
}
