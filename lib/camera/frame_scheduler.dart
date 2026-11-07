import 'dart:async';
import 'dart:developer' as developer;

import '../settings/app_settings.dart';
import 'camera_frame.dart';

/// Signature of the work the scheduler runs for an accepted frame.
typedef FrameHandler = Future<void> Function(CameraFrame frame);

/// Monotonic time since an arbitrary origin.
typedef MonotonicClock = Duration Function();

/// What happened to an offered frame.
enum FrameDecision {
  accepted,

  /// An inference is still running. Frames are never queued.
  droppedBusy,

  /// Too soon after the previous accepted frame.
  droppedRate,
}

/// Decides which camera frames reach the detector.
///
/// Rules (CLAUDE.md):
/// - Start at most [AppSettings.targetInferencesPerSecond] inferences/sec.
/// - If an inference is still running, DROP the new frame. Never queue.
class FrameScheduler {
  FrameScheduler({
    required this.settings,
    required FrameHandler onFrame,
    MonotonicClock? clock,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _onFrame = onFrame,
       _clock = clock ?? _stopwatchClock(),
       _onError = onError ?? _defaultOnError;

  /// Read on every offer, so a new rate applies from the next frame.
  AppSettings settings;

  final FrameHandler _onFrame;
  final MonotonicClock _clock;
  final void Function(Object error, StackTrace stackTrace) _onError;

  bool _busy = false;
  Duration? _lastAcceptedAt;
  int _accepted = 0;
  int _droppedBusy = 0;
  int _droppedRate = 0;

  /// Whether an accepted frame is still being processed.
  bool get isBusy => _busy;

  int get acceptedCount => _accepted;
  int get droppedBusyCount => _droppedBusy;
  int get droppedRateCount => _droppedRate;

  /// Offers a frame, which is either started now or dropped.
  FrameDecision offer(CameraFrame frame) {
    if (_busy) {
      _droppedBusy++;
      return FrameDecision.droppedBusy;
    }
    final Duration now = _clock();
    final Duration? last = _lastAcceptedAt;
    if (last != null && now - last < settings.minInferenceInterval) {
      _droppedRate++;
      return FrameDecision.droppedRate;
    }
    _lastAcceptedAt = now;
    _accepted++;
    _busy = true;
    unawaited(_process(frame));
    return FrameDecision.accepted;
  }

  /// Makes the next offered frame eligible at once (e.g. after resume). A
  /// running inference still blocks it. Counters are kept.
  void resetRateLimit() => _lastAcceptedAt = null;

  Future<void> _process(CameraFrame frame) async {
    try {
      await _onFrame(frame);
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    } finally {
      _busy = false;
    }
  }

  static MonotonicClock _stopwatchClock() {
    final Stopwatch stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  static void _defaultOnError(Object error, StackTrace stackTrace) {
    developer.log(
      'frame processing failed',
      name: 'camera',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
