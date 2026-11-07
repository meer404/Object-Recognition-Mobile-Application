import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/recognition_pipeline.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/detection/object_detector.dart';
import 'package:kurdish_vision/detection/yolo_detector.dart';
import 'package:kurdish_vision/metrics/metrics_logger.dart';
import 'package:kurdish_vision/settings/app_settings.dart';
import 'package:kurdish_vision/speech/speech_service.dart';

const int _table = 60;
const int _cup = 41;

DetectionResult _det(
  int classId, {
  double confidence = 0.9,
  double x = 0.5,
  double size = 0.3,
}) => DetectionResult(
  classId: classId,
  confidence: confidence,
  box: Rect.fromCenter(center: Offset(x, 0.5), width: size, height: size),
  position: HorizontalPosition.fromCenterX(x, const AppSettings()),
);

class _FakeDetector implements ObjectDetector {
  List<DetectionResult> next = <DetectionResult>[];
  Object? error;
  Completer<void>? gate;
  bool loaded = false;
  bool disposed = false;
  Object? loadError;

  @override
  bool get isLoaded => loaded;

  @override
  Future<void> load() async {
    if (loadError != null) throw loadError!;
    loaded = true;
  }

  @override
  Future<DetectionOutput> detect(CameraFrame frame) async {
    final List<DetectionResult> result = next;
    await gate?.future;
    if (error != null) throw error!;
    return DetectionOutput(
      detections: result,
      imageWidth: 480,
      imageHeight: 640,
      timings: const DetectionTimings(
        preprocessingMs: 1,
        inferenceMs: 2,
        postprocessingMs: 3,
      ),
    );
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _FakeSpeech implements SpeechService {
  final List<SpeechRequest> spoken = <SpeechRequest>[];
  final StreamController<bool> _events = StreamController<bool>.broadcast();
  bool busy = false;
  int stops = 0;
  int inits = 0;
  final List<double> volumes = <double>[];
  SpeechOutcome outcome = SpeechOutcome.started;

  List<String> get texts => <String>[
    for (final SpeechRequest r in spoken) r.text,
  ];

  @override
  Future<void> init() async => inits++;

  @override
  Future<bool> get supportsSorani async => true;

  @override
  Future<SpeechOutcome> speak(SpeechRequest request) async {
    spoken.add(request);
    return outcome;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  bool get speaking => busy;

  @override
  Stream<bool> get isSpeaking => _events.stream;

  @override
  Future<void> dispose() => _events.close();
}

void main() {
  late _FakeDetector detector;
  late _FakeSpeech speech;
  late DateTime now;
  late List<FrameMetrics> metrics;
  late int lost;
  late RecognitionPipeline pipeline;

  CameraFrame frame() => CameraFrame(
    width: 4,
    height: 4,
    format: FrameFormat.bgra8888,
    planes: <FramePlane>[FramePlane(bytes: Uint8List(64), bytesPerRow: 16)],
    timestamp: now.subtract(const Duration(milliseconds: 100)),
  );

  /// Runs [count] frames that see [detections].
  Future<void> see(List<DetectionResult> detections, {int count = 1}) async {
    detector.next = detections;
    for (int i = 0; i < count; i++) {
      await pipeline.processFrame(frame());
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    detector = _FakeDetector();
    speech = _FakeSpeech();
    now = DateTime.utc(2026);
    metrics = <FrameMetrics>[];
    lost = 0;
    pipeline = RecognitionPipeline(
      detector: detector,
      speech: speech,
      settings: const AppSettings(),
      now: () => now,
      onMetrics: metrics.add,
      onDetectorLost: () => lost++,
    );
    await pipeline.load();
  });

  group('announcing', () {
    test('an object is spoken once it is confirmed, not before', () async {
      await see(<DetectionResult>[_det(_table)]);
      expect(speech.spoken, isEmpty);
      await see(<DetectionResult>[_det(_table)]);
      expect(speech.texts, <String>['لەبەردەمت مێزێک هەیە.']);
    });

    test('low-confidence results are never spoken', () async {
      await see(<DetectionResult>[_det(_table, confidence: 0.49)], count: 5);
      expect(speech.spoken, isEmpty);
    });

    test('it is not repeated until the cooldown has passed', () async {
      await see(<DetectionResult>[_det(_table)], count: 4);
      expect(speech.spoken, hasLength(1));

      now = now.add(const Duration(seconds: 5));
      await see(<DetectionResult>[_det(_table)]);
      expect(speech.spoken, hasLength(2));
    });

    test('moving to another region is announced at once', () async {
      // Wide boxes, so the moves stay on one track.
      await see(<DetectionResult>[_det(_table, size: 0.6)], count: 2);
      await see(<DetectionResult>[_det(_table, x: 0.8, size: 0.6)]);
      expect(speech.texts.last, 'لای ڕاست مێزێک هەیە.');
    });

    test('an object that left and came back is announced again', () async {
      await see(<DetectionResult>[_det(_table)], count: 2);
      await see(<DetectionResult>[], count: 3);
      await see(<DetectionResult>[_det(_table)], count: 2);
      expect(speech.spoken, hasLength(2));
    });

    test('several objects share one sentence', () async {
      await see(<DetectionResult>[
        _det(_table, size: 0.5, x: 0.5),
        _det(_cup, size: 0.1, x: 0.1),
      ], count: 2);
      expect(speech.texts.single, 'لەبەردەمت مێزێک هەیە. پەرداخێکیش دەبینرێت.');
    });

    test('while speaking, nothing new is sent and objects stay due', () async {
      speech.busy = true;
      await see(<DetectionResult>[_det(_table)], count: 3);
      expect(speech.spoken, isEmpty);

      speech.busy = false;
      await see(<DetectionResult>[_det(_table)]);
      expect(speech.spoken, hasLength(1), reason: 'must not be lost');
    });

    test('objects beyond the sentence limit are announced next', () async {
      // Well separated, and largest first: 73 and 74 do not fit in the sentence.
      final List<DetectionResult> four = <DetectionResult>[
        _det(_table, size: 0.20, x: 0.1),
        _det(_cup, size: 0.15, x: 0.35),
        _det(56, size: 0.12, x: 0.6),
        _det(73, size: 0.10, x: 0.85),
      ];
      await see(four, count: 2);
      expect(speech.spoken.first.clipKeys, isNot(contains('class_73_also')));
      await see(four);
      expect(speech.spoken, hasLength(2));
      expect(speech.spoken.last.clipKeys, contains('class_73'));
    });
  });

  group('repeat', () {
    test('speaks what is confirmed now, cutting off current speech', () async {
      await see(<DetectionResult>[_det(_table)], count: 2);
      pipeline.repeat();
      await Future<void>.delayed(Duration.zero);
      expect(speech.spoken, hasLength(2));
      expect(speech.spoken.last.interrupt, isTrue);
      expect(speech.spoken.last.text, speech.spoken.first.text);
    });

    test('works even within the cooldown', () async {
      await see(<DetectionResult>[_det(_table)], count: 2);
      pipeline.repeat();
      pipeline.repeat();
      await Future<void>.delayed(Duration.zero);
      expect(speech.spoken, hasLength(3));
    });

    test(
      'restarts the cooldown, so it is not said again right after',
      () async {
        await see(<DetectionResult>[_det(_table)], count: 2);
        now = now.add(const Duration(seconds: 4));
        pipeline.repeat();
        now = now.add(const Duration(seconds: 2));
        await see(<DetectionResult>[_det(_table)]);
        expect(speech.spoken, hasLength(2));
      },
    );

    test('says so when nothing is confirmed', () async {
      await see(<DetectionResult>[_det(_table)]);
      pipeline.repeat();
      await Future<void>.delayed(Duration.zero);
      expect(speech.spoken.single.clipKeys, <String>['nothing_detected']);
      expect(speech.spoken.single.interrupt, isTrue);
    });

    test('does nothing before speech is ready', () {
      final _FakeSpeech fresh = _FakeSpeech();
      RecognitionPipeline(
        detector: detector,
        speech: fresh,
        settings: const AppSettings(),
      ).repeat();
      expect(fresh.spoken, isEmpty);
    });
  });

  group('reset', () {
    test('stops speech and forgets the scene', () async {
      await see(<DetectionResult>[_det(_table)], count: 2);
      pipeline.reset();
      expect(speech.stops, 1);
      expect(pipeline.latestOutput.value, isNull);

      await see(<DetectionResult>[_det(_table)]);
      expect(speech.spoken, hasLength(1), reason: 'needs confirming again');
      await see(<DetectionResult>[_det(_table)]);
      expect(speech.spoken, hasLength(2), reason: 'announced afresh');
    });

    test('a result from before the reset is ignored', () async {
      await see(<DetectionResult>[_det(_table)]);
      detector.gate = Completer<void>();
      final Future<void> inFlight = pipeline.processFrame(frame());
      pipeline.reset();
      detector.gate!.complete();
      await inFlight;
      expect(pipeline.latestOutput.value, isNull);
      expect(speech.spoken, isEmpty);
    });
  });

  group('failures', () {
    test('a failed frame does not stop the pipeline', () async {
      detector.error = const DetectorException('one bad frame');
      await see(<DetectionResult>[_det(_table)]);
      expect(lost, 0, reason: 'the detector is still loaded');

      detector.error = null;
      await see(<DetectionResult>[_det(_table)], count: 2);
      expect(speech.spoken, hasLength(1));
    });

    test('a lost detector is reported', () async {
      detector.loaded = false;
      detector.error = const DetectorException('worker stopped');
      await see(<DetectionResult>[]);
      expect(lost, 1);
    });

    test('a load failure reaches the caller and can be retried', () async {
      final _FakeDetector broken = _FakeDetector()
        ..loadError = StateError('no model');
      final _FakeSpeech fresh = _FakeSpeech();
      final RecognitionPipeline p = RecognitionPipeline(
        detector: broken,
        speech: fresh,
        settings: const AppSettings(),
      );
      await expectLater(p.load(), throwsStateError);
      expect(fresh.inits, 0);

      broken.loadError = null;
      await p.load();
      await p.load();
      expect(fresh.inits, 1, reason: 'speech prepared only once');
    });
  });

  group('metrics', () {
    test('every frame is reported with its stage timings', () async {
      await see(<DetectionResult>[_det(_table)]);
      expect(metrics, hasLength(1));
      expect(metrics.single.preprocessingMs, 1);
      expect(metrics.single.inferenceMs, 2);
      expect(metrics.single.postprocessingMs, 3);
      expect(metrics.single.detectionCount, 1);
      expect(metrics.single.frameToSpeechStartMs, isNull);
    });

    test('a frame that started speech reports its latency', () async {
      await see(<DetectionResult>[_det(_table)], count: 2);
      expect(metrics, hasLength(2));
      expect(metrics.last.frameToSpeechStartMs, 100);
    });

    test('speech that did not start reports no latency', () async {
      speech.outcome = SpeechOutcome.nothingToSay;
      await see(<DetectionResult>[_det(_table)], count: 2);
      expect(metrics.last.frameToSpeechStartMs, isNull);
    });
  });

  test('settings changes reach speech volume', () {
    pipeline.updateSettings(const AppSettings(speechVolume: 0.4));
    expect(speech.volumes, <double>[0.4]);
  });

  test('dispose releases the detector', () async {
    await pipeline.dispose();
    expect(detector.disposed, isTrue);
  });
}
