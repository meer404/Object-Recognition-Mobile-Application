import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../camera/camera_frame.dart';
import '../detection/detection_filter.dart';
import '../detection/detection_result.dart';
import '../detection/object_detector.dart';
import '../detection/tracker.dart';
import '../detection/yolo_detector.dart';
import '../metrics/metrics_logger.dart';
import '../settings/app_settings.dart';
import '../speech/phrase_builder.dart';
import '../speech/speech_service.dart';

/// Detector → DetectionFilter & Tracker → PhraseBuilder → SpeechOutput.
///
/// New objects are only announced while speech is idle. An object that has to
/// wait stays due, so what is said reflects the scene when speech is free,
/// not a queue of old sentences.
class RecognitionPipeline {
  RecognitionPipeline({
    required ObjectDetector detector,
    required SpeechService speech,
    required AppSettings settings,
    DateTime Function()? now,
    void Function(FrameMetrics metrics)? onMetrics,
    this.onDetectorLost,
  }) : _detector = detector,
       _speech = speech,
       _filter = DetectionFilter(settings: settings),
       _tracker = Tracker(settings: settings),
       _phrases = PhraseBuilder(settings: settings),
       _now = now ?? DateTime.now,
       _onMetrics = onMetrics;

  final ObjectDetector _detector;
  final SpeechService _speech;
  final DetectionFilter _filter;
  final Tracker _tracker;
  final PhraseBuilder _phrases;
  final DateTime Function() _now;
  final void Function(FrameMetrics metrics)? _onMetrics;

  /// Called when the detector has stopped for good and needs reloading.
  VoidCallback? onDetectorLost;

  /// The latest detector result, for the debug overlay.
  final ValueNotifier<DetectionOutput?> latestOutput =
      ValueNotifier<DetectionOutput?>(null);

  FilterResult? _latest;
  bool _speechReady = false;

  /// Bumped by [reset], so a result from before a pause is ignored.
  int _generation = 0;

  /// Loads the model and prepares speech. Safe to call again after a failure.
  Future<void> load() async {
    await _detector.load();
    if (!_speechReady) {
      await _speech.init();
      _speechReady = true;
    }
  }

  void updateSettings(AppSettings settings) {
    _filter.settings = settings;
    _tracker.settings = settings;
    _phrases.settings = settings;
    unawaited(_speech.setVolume(settings.speechVolume));
  }

  /// The FrameScheduler's work for one accepted frame.
  Future<void> processFrame(CameraFrame frame) async {
    final int generation = _generation;
    final DetectionOutput output;
    try {
      output = await _detector.detect(frame);
    } on DetectorException catch (e) {
      developer.log('detection failed: $e', name: 'pipeline');
      if (!_detector.isLoaded && generation == _generation) {
        onDetectorLost?.call();
      }
      return;
    }
    if (generation != _generation) return;

    latestOutput.value = output;
    final FilterResult result = _filter.update(output.detections);
    _latest = result;

    final DateTime now = _now();
    final SpeechRequest? request = _speech.speaking
        ? null
        : _announceDue(result, now);
    if (request == null) {
      _report(frame, output);
    } else {
      _speak(request, frame, output);
    }
  }

  /// The user's Repeat: speaks what is confirmed now, cutting off current
  /// speech. Says so if nothing is, rather than staying silent.
  void repeat() {
    if (!_speechReady) return;
    final FilterResult? result = _latest;
    final List<TrackedDetection> confirmed =
        result?.confirmed ?? const <TrackedDetection>[];
    final Phrase? phrase = _phrases.build(<DetectionResult>[
      for (final TrackedDetection t in confirmed) t.detection,
    ], interrupt: true);
    if (phrase == null) {
      _speak(_phrases.nothingDetected(), null, null);
      return;
    }
    _tracker.markAnnounced(
      confirmed.where(
        (TrackedDetection t) => phrase.classes.contains(t.detection.classId),
      ),
      _now(),
    );
    _speak(phrase.request, null, null);
  }

  /// Forgets the scene and stops speech (the user paused, or the app left the
  /// screen). The scene may have changed by the time it resumes.
  void reset() {
    _generation++;
    _filter.reset();
    _tracker.reset();
    _latest = null;
    latestOutput.value = null;
    if (_speechReady) unawaited(_speech.stop());
  }

  Future<void> dispose() async {
    _generation++;
    latestOutput.dispose();
    await _detector.dispose();
    await _speech.dispose();
  }

  SpeechRequest? _announceDue(FilterResult result, DateTime now) {
    final List<TrackedDetection> due = _tracker.objectsToAnnounce(result, now);
    final Phrase? phrase = _phrases.build(<DetectionResult>[
      for (final TrackedDetection t in due) t.detection,
    ]);
    if (phrase == null) return null;
    // Only what is actually named counts as announced; the rest stays due.
    _tracker.markAnnounced(
      due.where(
        (TrackedDetection t) => phrase.classes.contains(t.detection.classId),
      ),
      now,
    );
    return phrase.request;
  }

  void _speak(
    SpeechRequest request,
    CameraFrame? frame,
    DetectionOutput? output,
  ) {
    unawaited(
      _speech
          .speak(request)
          .then(
            (SpeechOutcome outcome) {
              if (frame == null || output == null) return;
              final double? latency = outcome == SpeechOutcome.started
                  ? _now().difference(frame.timestamp).inMicroseconds / 1000
                  : null;
              _report(frame, output, frameToSpeechStartMs: latency);
            },
            onError: (Object error, StackTrace stackTrace) {
              developer.log(
                'speech failed',
                name: 'pipeline',
                error: error,
                stackTrace: stackTrace,
              );
              if (frame != null && output != null) _report(frame, output);
            },
          ),
    );
  }

  void _report(
    CameraFrame frame,
    DetectionOutput output, {
    double? frameToSpeechStartMs,
  }) {
    _onMetrics?.call(
      FrameMetrics(
        timestamp: frame.timestamp,
        preprocessingMs: output.timings.preprocessingMs,
        inferenceMs: output.timings.inferenceMs,
        postprocessingMs: output.timings.postprocessingMs,
        detectionCount: output.detections.length,
        frameToSpeechStartMs: frameToSpeechStartMs,
      ),
    );
  }
}
