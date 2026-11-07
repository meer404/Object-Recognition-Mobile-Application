import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/metrics/metrics_logger.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

void main() {
  final DateTime t = DateTime.utc(2026, 11, 8, 14, 30, 5, 123);

  group('frames.csv', () {
    test('a row has one value per header column, in order', () {
      final String row = frameCsvRow(
        FrameMetrics(
          timestamp: t,
          preprocessingMs: 1.23456,
          inferenceMs: 20,
          postprocessingMs: 0.5,
          detectionCount: 3,
          frameToSpeechStartMs: 180.25,
        ),
      );
      expect(row.split(','), hasLength(frameCsvHeader.split(',').length));
      expect(
        row,
        '2026-11-08T14:30:05.123Z,1.235,20.000,0.500,21.735,3,180.250',
      );
    });

    test('no speech leaves the latency empty, not zero', () {
      final String row = frameCsvRow(
        FrameMetrics(
          timestamp: t,
          preprocessingMs: 1,
          inferenceMs: 2,
          postprocessingMs: 3,
          detectionCount: 0,
        ),
      );
      expect(row.endsWith(',0,'), isTrue);
    });

    test('local times are written as UTC', () {
      final String row = frameCsvRow(
        FrameMetrics(
          timestamp: t.toLocal(),
          preprocessingMs: 0,
          inferenceMs: 0,
          postprocessingMs: 0,
          detectionCount: 0,
        ),
      );
      expect(row.startsWith('2026-11-08T14:30:05.123Z,'), isTrue);
    });
  });

  group('device.csv', () {
    test('a row has one value per header column, in order', () {
      final String row = deviceCsvRow(
        DeviceSample(
          timestamp: t,
          rssMb: 312.456,
          batteryPercent: 87,
          batteryState: 'discharging',
          cameraFps: 29.987,
          inferenceFps: 3.75,
          droppedBusy: 4,
          droppedRate: 260,
        ),
      );
      expect(row.split(','), hasLength(deviceCsvHeader.split(',').length));
      expect(
        row,
        '2026-11-08T14:30:05.123Z,312.5,87,discharging,29.99,3.75,4,260',
      );
    });

    test('unknown values are empty', () {
      final String row = deviceCsvRow(
        DeviceSample(
          timestamp: t,
          rssMb: 100,
          batteryPercent: null,
          batteryState: 'unknown',
          cameraFps: null,
          inferenceFps: double.nan,
          droppedBusy: 0,
          droppedRate: 0,
        ),
      );
      expect(row, '2026-11-08T14:30:05.123Z,100.0,,unknown,,,0,0');
    });
  });

  test('csvField quotes only when needed', () {
    expect(csvField('plain'), 'plain');
    expect(csvField('a,b'), '"a,b"');
    expect(csvField('say "hi"'), '"say ""hi"""');
    expect(csvField('two\nlines'), '"two\nlines"');
  });

  group('session.json', () {
    SessionInfo info(String mode) => SessionInfo(
      startedAt: t,
      buildMode: mode,
      appVersion: '1.0.0+1',
      gitCommit: 'abc123',
      device: 'Test Phone',
      os: 'Android 15 (API 35)',
      accelerator: 'gpu (OpenGL/OpenCL)',
      modelAsset: 'assets/models/yolo26n_320_fp32.tflite',
      modelBytes: 9894796,
      settings: const AppSettings().toJson(),
    );

    test('records what the session ran on', () {
      final Map<String, dynamic> json =
          jsonDecode(info('release').toPrettyJson()) as Map<String, dynamic>;
      expect(json['started_utc'], '2026-11-08T14:30:05.123Z');
      expect(json['build_mode'], 'release');
      expect(json['accelerator'], 'gpu (OpenGL/OpenCL)');
      expect(json['model_bytes'], 9894796);
      expect((json['settings'] as Map<String, dynamic>)['modelInputSize'], 320);
    });

    test('debug sessions are flagged as invalid for performance claims', () {
      Map<String, dynamic> parse(String mode) =>
          jsonDecode(info(mode).toPrettyJson()) as Map<String, dynamic>;
      expect(parse('debug')['valid_for_performance_claims'], isFalse);
      expect(parse('profile')['valid_for_performance_claims'], isTrue);
      expect(parse('release')['valid_for_performance_claims'], isTrue);
    });
  });

  test('AppSettings.toJson includes every setting', () {
    // Counts the fields declared in AppSettings, so a new setting cannot be
    // left out of session.json unnoticed.
    final String source = File(
      'lib/settings/app_settings.dart',
    ).readAsStringSync();
    final int fields = RegExp(
      r'^  final [A-Za-z]+ [a-zA-Z]+;$',
      multiLine: true,
    ).allMatches(source).length;
    expect(fields, greaterThan(15));
    expect(const AppSettings().toJson(), hasLength(fields));
  });
}
