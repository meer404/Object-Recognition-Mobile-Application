import 'dart:async';
import 'dart:developer' as developer;

import 'speech_service.dart';

/// Plays [item]; must call [onStarted] when audio actually begins and
/// complete when playback ends (finished or stopped).
typedef SpeechPerformer<T> =
    Future<void> Function(T item, void Function() onStarted);

/// Enforces the speech overlap rule for any back-end (D-008):
///
/// - At most one item is performed at a time.
/// - While busy, only the NEWEST submitted item waits. An older waiting
///   item is dropped and its future completes with [SpeechOutcome.dropped].
/// - `submit(interrupt: true)` cuts the current item off and plays the new
///   item next.
/// - [stop] cuts the current item off and drops the waiting one.
///
/// Like the FrameScheduler, it drops old work instead of queueing: stale
/// descriptions of the scene are worse than none.
class SpeechSerializer<T> {
  SpeechSerializer({
    required SpeechPerformer<T> perform,
    required Future<void> Function() stopCurrent,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _perform = perform,
       _stopCurrent = stopCurrent,
       _onError = onError ?? _defaultOnError;

  final SpeechPerformer<T> _perform;
  final Future<void> Function() _stopCurrent;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final StreamController<bool> _speakingController =
      StreamController<bool>.broadcast();

  _Job<T>? _current;
  _Job<T>? _pending;
  bool _disposed = false;

  /// Whether an item is being performed right now.
  bool get speaking => _current != null;

  /// Emits true on idle → speaking and false on speaking → idle.
  Stream<bool> get isSpeaking => _speakingController.stream;

  /// Submits [item]. See the class docs for the overlap rule.
  Future<SpeechOutcome> submit(T item, {bool interrupt = false}) {
    if (_disposed) {
      return Future<SpeechOutcome>.value(SpeechOutcome.dropped);
    }
    final _Job<T> job = _Job<T>(item);
    final _Job<T>? current = _current;
    if (current == null) {
      _speakingController.add(true);
      _start(job);
    } else {
      _pending?.resolve(SpeechOutcome.dropped);
      _pending = job;
      if (interrupt) _cancel(current);
    }
    return job.outcome;
  }

  /// Stops current speech and drops the waiting item.
  Future<void> stop() async {
    _pending?.resolve(SpeechOutcome.dropped);
    _pending = null;
    final _Job<T>? current = _current;
    if (current != null) await _cancel(current);
  }

  /// Stops everything and closes [isSpeaking]. Later submits are dropped.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _speakingController.close();
  }

  Future<void> _cancel(_Job<T> job) {
    job.cancelled = true;
    return _stopCurrent().catchError(_onError);
  }

  void _start(_Job<T> job) {
    _current = job;
    Future<void> run;
    try {
      run = _perform(job.item, () => job.resolve(SpeechOutcome.started));
    } catch (error, stackTrace) {
      run = Future<void>.error(error, stackTrace);
    }
    run.then(
      (_) => _finish(job),
      onError: (Object error, StackTrace stackTrace) {
        _onError(error, stackTrace);
        _finish(job);
      },
    );
  }

  void _finish(_Job<T> job) {
    // Ended without ever starting: deliberate stop → dropped, else failed.
    job.resolve(job.cancelled ? SpeechOutcome.dropped : SpeechOutcome.failed);
    if (!identical(_current, job)) return;
    _current = null;
    final _Job<T>? next = _pending;
    _pending = null;
    if (next != null && !_disposed) {
      _start(next);
    } else if (!_speakingController.isClosed) {
      _speakingController.add(false);
    }
  }

  static void _defaultOnError(Object error, StackTrace stackTrace) {
    developer.log(
      'speech playback error',
      name: 'speech',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _Job<T> {
  _Job(this.item);

  final T item;
  final Completer<SpeechOutcome> _completer = Completer<SpeechOutcome>();
  bool cancelled = false;

  Future<SpeechOutcome> get outcome => _completer.future;

  void resolve(SpeechOutcome value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }
}
