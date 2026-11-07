import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/detection/detection_engine.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/detection/model_runner.dart';
import 'package:kurdish_vision/detection/object_detector.dart';
import 'package:kurdish_vision/detection/yolo_detector.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

const int _channels = 6; // 4 box values + 2 classes.
const int _anchors = 1;
const AppSettings _settings = AppSettings(modelInputSize: 8);

CameraFrame _frame({int width = 4, int height = 8}) => CameraFrame(
  width: width,
  height: height,
  format: FrameFormat.bgra8888,
  planes: <FramePlane>[
    FramePlane(bytes: Uint8List(width * height * 4), bytesPerRow: width * 4),
  ],
  timestamp: DateTime.utc(2026),
);

/// One detection of class 1 at the centre, score 0.9.
class _FakeRunner implements ModelRunner {
  @override
  int get channels => _channels;

  @override
  int get anchors => _anchors;

  @override
  String get accelerator => 'fake';

  @override
  Float32List run(Float32List input) =>
      Float32List.fromList(<double>[0.5, 0.5, 0.5, 0.5, 0.0, 0.9]);

  @override
  void close() {}
}

ModelRunner _workingFactory(Uint8List bytes, int size, int threads) =>
    _FakeRunner();

ModelRunner _failingFactory(Uint8List bytes, int size, int threads) =>
    throw const ModelFormatException('bad model');

class _ThrowingRunner extends _FakeRunner {
  @override
  Float32List run(Float32List input) => throw StateError('inference failed');
}

ModelRunner _throwingFactory(Uint8List bytes, int size, int threads) =>
    _ThrowingRunner();

class _KillingRunner extends _FakeRunner {
  @override
  Float32List run(Float32List input) => Isolate.exit();
}

ModelRunner _killingFactory(Uint8List bytes, int size, int threads) =>
    _KillingRunner();

YoloDetector _detector(
  ModelRunnerFactory factory, {
  AppSettings settings = _settings,
}) => YoloDetector(
  settings: settings,
  allowedClasses: const <int>{1},
  loadModelBytes: () async => Uint8List(4),
  runnerFactory: factory,
);

double _iou(Rect a, Rect b) {
  final Rect overlap = a.intersect(b);
  if (overlap.width <= 0 || overlap.height <= 0) return 0;
  final double inter = overlap.width * overlap.height;
  return inter / (a.width * a.height + b.width * b.height - inter);
}

void main() {
  group('DetectionEngine', () {
    test('runs every stage and reports timings and image size', () {
      final DetectionOutput output = DetectionEngine(
        runner: _FakeRunner(),
        settings: _settings,
        allowedClasses: const <int>{1},
      ).process(_frame());
      expect(output.detections.single.classId, 1);
      expect(output.imageWidth, 4);
      expect(output.imageHeight, 8);
      expect(output.timings.preprocessingMs, greaterThanOrEqualTo(0));
      expect(output.timings.inferenceMs, greaterThanOrEqualTo(0));
      expect(output.timings.postprocessingMs, greaterThanOrEqualTo(0));
    });

    test('applies rotation to the reported image size', () {
      final DetectionOutput output =
          DetectionEngine(
            runner: _FakeRunner(),
            settings: _settings,
            allowedClasses: const <int>{1},
          ).process(
            CameraFrame(
              width: 8,
              height: 4,
              format: FrameFormat.bgra8888,
              planes: <FramePlane>[
                FramePlane(bytes: Uint8List(128), bytesPerRow: 32),
              ],
              timestamp: DateTime.utc(2026),
              rotationDegrees: 90,
            ),
          );
      expect(output.imageWidth, 4);
      expect(output.imageHeight, 8);
    });
  });

  group('YoloDetector', () {
    test('detects through the worker isolate', () async {
      final YoloDetector detector = _detector(_workingFactory);
      expect(detector.isLoaded, isFalse);
      await detector.load();
      expect(detector.isLoaded, isTrue);
      expect(detector.accelerator, 'fake');

      final DetectionOutput output = await detector.detect(_frame());
      expect(output.detections.single.classId, 1);
      expect(output.detections.single.confidence, closeTo(0.9, 1e-6));
      await detector.dispose();
    });

    test('serves several frames', () async {
      final YoloDetector detector = _detector(_workingFactory);
      await detector.load();
      for (int i = 0; i < 3; i++) {
        expect((await detector.detect(_frame())).detections, hasLength(1));
      }
      await detector.dispose();
    });

    test('load fails when the model cannot be used', () async {
      final YoloDetector detector = _detector(_failingFactory);
      await expectLater(detector.load(), throwsA(isA<DetectorException>()));
      expect(detector.isLoaded, isFalse);
    });

    test('load fails when the model file is missing', () async {
      final YoloDetector detector = YoloDetector(
        settings: _settings,
        allowedClasses: const <int>{1},
        loadModelBytes: () => Future<Uint8List>.error(StateError('no asset')),
        runnerFactory: _workingFactory,
      );
      await expectLater(detector.load(), throwsStateError);
      expect(detector.isLoaded, isFalse);
    });

    test('detect before load fails instead of hanging', () async {
      await expectLater(
        _detector(_workingFactory).detect(_frame()),
        throwsA(isA<DetectorException>()),
      );
    });

    test(
      'a failed inference fails that frame; the detector stays up',
      () async {
        final YoloDetector detector = _detector(_throwingFactory);
        await detector.load();
        await expectLater(
          detector.detect(_frame()),
          throwsA(isA<DetectorException>()),
        );
        expect(detector.isLoaded, isTrue);
        await detector.dispose();
      },
    );

    test('a worker that dies fails the waiting frame, not a hang', () async {
      final YoloDetector detector = _detector(_killingFactory);
      await detector.load();
      await expectLater(
        detector.detect(_frame()),
        throwsA(isA<DetectorException>()),
      );
      expect(detector.isLoaded, isFalse);
    });

    test('detect after dispose fails', () async {
      final YoloDetector detector = _detector(_workingFactory);
      await detector.load();
      await detector.dispose();
      expect(detector.isLoaded, isFalse);
      await expectLater(
        detector.detect(_frame()),
        throwsA(isA<DetectorException>()),
      );
    });
  });

  group('real model', () {
    final File model = File('assets/models/yolo26n_320_fp32.tflite');
    final bool available = model.existsSync();

    test(
      'loads and runs in a background isolate',
      skip: available
          ? false
          : 'model file is git-ignored: see tools/export_model.py',
      () async {
        final YoloDetector detector = YoloDetector(
          settings: const AppSettings(),
          allowedClasses: const <int>{0},
          loadModelBytes: model.readAsBytes,
        );
        await detector.load();
        final DetectionOutput output = await detector.detect(
          _frame(width: 64, height: 48),
        );
        // A black image: the point is that the real tensor shapes work.
        expect(output.detections, isEmpty);
        expect(output.timings.inferenceMs, greaterThan(0));
        await detector.dispose();
      },
    );

    // Real photo frames from tools/make_detector_fixtures.py (build/, not committed).
    final File photoInfo = File('build/fixtures/photo_frames.json');
    final bool photoAvailable = available && photoInfo.existsSync();

    group('on a real photo', () {
      late Map<String, dynamic> info;
      late YoloDetector detector;

      setUpAll(() async {
        if (!photoAvailable) return;
        info = jsonDecode(photoInfo.readAsStringSync()) as Map<String, dynamic>;
        detector = YoloDetector(
          settings: const AppSettings(),
          allowedClasses: const <int>{0, 5}, // person, bus
          loadModelBytes: model.readAsBytes,
        );
        await detector.load();
      });

      tearDownAll(() async {
        if (photoAvailable) await detector.dispose();
      });

      Uint8List bytes(String name) =>
          File('build/fixtures/$name').readAsBytesSync();

      /// Every reference detection must be found: same class, IoU >= 0.8.
      void expectReference(DetectionOutput output) {
        final List<dynamic> expected = info['expected'] as List<dynamic>;
        expect(expected, isNotEmpty);
        for (final dynamic item in expected) {
          final Map<String, dynamic> e = item as Map<String, dynamic>;
          final List<dynamic> b = e['box'] as List<dynamic>;
          final Rect box = Rect.fromLTRB(
            (b[0] as num).toDouble(),
            (b[1] as num).toDouble(),
            (b[2] as num).toDouble(),
            (b[3] as num).toDouble(),
          );
          double best = 0;
          for (final DetectionResult d in output.detections) {
            if (d.classId != e['class']) continue;
            final double v = _iou(d.box, box);
            if (v > best) best = v;
          }
          expect(best, greaterThanOrEqualTo(0.8), reason: 'reference $e');
        }
      }

      test(
        'upright BGRA frame finds the reference objects',
        skip: photoAvailable ? false : 'run tools/make_detector_fixtures.py',
        () async {
          final int w = info['width'] as int;
          final int h = info['height'] as int;
          expectReference(
            await detector.detect(
              CameraFrame(
                width: w,
                height: h,
                format: FrameFormat.bgra8888,
                planes: <FramePlane>[
                  FramePlane(
                    bytes: bytes('photo_upright.bgra'),
                    bytesPerRow: w * 4,
                  ),
                ],
                timestamp: DateTime.utc(2026),
              ),
            ),
          );
        },
      );

      test(
        'rotated YUV frame, as Android delivers it, finds them in place',
        skip: photoAvailable ? false : 'run tools/make_detector_fixtures.py',
        () async {
          // Sensor frame: the upright photo turned 90 degrees counter-clockwise.
          final int w = info['height'] as int;
          final int h = info['width'] as int;
          final int chromaWidth = w ~/ 2;
          final DetectionOutput output = await detector.detect(
            CameraFrame(
              width: w,
              height: h,
              format: FrameFormat.yuv420,
              rotationDegrees: 90,
              planes: <FramePlane>[
                FramePlane(
                  bytes: bytes('photo_sensor.y'),
                  bytesPerRow: w,
                  bytesPerPixel: 1,
                ),
                FramePlane(
                  bytes: bytes('photo_sensor.u'),
                  bytesPerRow: chromaWidth,
                  bytesPerPixel: 1,
                ),
                FramePlane(
                  bytes: bytes('photo_sensor.v'),
                  bytesPerRow: chromaWidth,
                  bytesPerPixel: 1,
                ),
              ],
              timestamp: DateTime.utc(2026),
            ),
          );
          expect(output.imageWidth, h);
          expect(output.imageHeight, w);
          expectReference(output);
        },
      );
    });

    test(
      'a model of the wrong input size is rejected clearly',
      skip: available ? false : 'model file is git-ignored',
      () async {
        final YoloDetector detector = YoloDetector(
          settings: const AppSettings(modelInputSize: 640),
          allowedClasses: const <int>{0},
          loadModelBytes: model.readAsBytes,
        );
        await expectLater(
          detector.load(),
          throwsA(
            isA<DetectorException>().having(
              (DetectorException e) => e.message,
              'message',
              contains('expected [1, 3, 640, 640]'),
            ),
          ),
        );
      },
    );
  });
}
