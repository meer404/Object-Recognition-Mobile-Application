import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../camera/camera_frame.dart';
import '../settings/app_settings.dart';
import 'detection_engine.dart';
import 'model_runner.dart';
import 'object_detector.dart';

/// Thrown by [YoloDetector.detect] if the worker fails or has stopped.
class DetectorException implements Exception {
  const DetectorException(this.message);

  final String message;

  @override
  String toString() => 'DetectorException: $message';
}

/// YOLO26n implementation of [ObjectDetector].
///
/// A single long-lived isolate does preprocessing, inference and postprocessing,
/// so the UI isolate is never blocked. It owns the interpreter because GPU
/// delegates are bound to the thread that created them.
class YoloDetector implements ObjectDetector {
  YoloDetector({
    required AppSettings settings,
    required Set<int> allowedClasses,
    required Future<Uint8List> Function() loadModelBytes,
    ModelRunnerFactory runnerFactory = createLiteRtRunner,
    this.inferenceThreads = 4,
  }) : _settings = settings,
       _allowedClasses = allowedClasses,
       _loadModelBytes = loadModelBytes,
       _runnerFactory = runnerFactory;

  final AppSettings _settings;
  final Set<int> _allowedClasses;
  final Future<Uint8List> Function() _loadModelBytes;
  final ModelRunnerFactory _runnerFactory;
  final int inferenceThreads;

  Isolate? _isolate;
  SendPort? _worker;
  Completer<void>? _ready;
  final Map<int, Completer<DetectionOutput>> _pending =
      <int, Completer<DetectionOutput>>{};
  int _nextId = 0;
  String? _accelerator;
  bool _closed = false;

  /// Bumped for every worker. Messages from an older worker are ignored, so a
  /// late exit event cannot disturb its replacement.
  int _generation = 0;

  /// Which accelerator the model runs on, once loaded.
  String? get accelerator => _accelerator;

  @override
  bool get isLoaded => _worker != null && !_closed;

  /// Whether a worker isolate exists, for tests of cleanup.
  @visibleForTesting
  bool get hasWorkerIsolate => _isolate != null;

  @override
  Future<void> load() async {
    if (isLoaded) return;
    if (_closed) throw const DetectorException('detector is disposed');
    final Uint8List bytes = await _loadModelBytes();
    if (_closed) {
      throw const DetectorException('detector was disposed while loading');
    }

    final int generation = ++_generation;
    final ReceivePort replies = ReceivePort();
    final ReceivePort exits = ReceivePort();
    final Completer<void> ready = Completer<void>();
    _ready = ready;
    replies.listen((Object? message) {
      if (generation == _generation) _onReply(message);
    });
    exits.listen((_) {
      replies.close();
      exits.close();
      if (generation == _generation) _failEverything('detector worker stopped');
    });

    try {
      _isolate = await Isolate.spawn<_WorkerStart>(
        _workerMain,
        _WorkerStart(
          replies: replies.sendPort,
          modelBytes: TransferableTypedData.fromList(<Uint8List>[bytes]),
          settings: _settings,
          allowedClasses: _allowedClasses,
          runnerFactory: _runnerFactory,
          threads: inferenceThreads,
        ),
        debugName: 'detector',
        onExit: exits.sendPort,
      );
    } catch (_) {
      replies.close();
      exits.close();
      rethrow;
    }
    await ready.future;
    if (_closed) {
      // dispose() ran while the worker was starting: do not leave it running.
      _shutdownWorker();
      throw const DetectorException('detector was disposed while loading');
    }
  }

  @override
  Future<DetectionOutput> detect(CameraFrame frame) {
    final SendPort? worker = _worker;
    if (worker == null || _closed) {
      return Future<DetectionOutput>.error(
        const DetectorException('detector is not loaded'),
      );
    }
    final int id = _nextId++;
    final Completer<DetectionOutput> completer = Completer<DetectionOutput>();
    _pending[id] = completer;
    worker.send(_DetectRequest(id, frame));
    final Duration limit = _settings.detectionTimeout;
    return completer.future.timeout(
      limit,
      onTimeout: () {
        // A stuck native call cannot be cancelled, only its isolate killed.
        final String error =
            'inference timed out after ${limit.inMilliseconds} ms';
        _pending.remove(id);
        _generation++;
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        _failEverything(error);
        throw DetectorException(error);
      },
    );
  }

  void _onReply(Object? message) {
    switch (message) {
      case _WorkerReady(:final SendPort requests, :final String accelerator):
        _worker = requests;
        _accelerator = accelerator;
        _ready?.complete();
      case _WorkerFailed(:final String error):
        _failEverything(error);
      case _DetectReply(:final int id, :final DetectionOutput output):
        _pending.remove(id)?.complete(output);
      case _DetectFailed(:final int id, :final String error):
        _pending.remove(id)?.completeError(DetectorException(error));
    }
  }

  void _failEverything(String error) {
    _worker = null;
    final Completer<void>? ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(DetectorException(error));
    }
    for (final Completer<DetectionOutput> c in _pending.values) {
      c.completeError(DetectorException(error));
    }
    _pending.clear();
  }

  /// Asks a ready worker to close its interpreter, or kills one still starting.
  void _shutdownWorker() {
    final SendPort? worker = _worker;
    if (worker != null) {
      worker.send(const _Shutdown());
    } else {
      _isolate?.kill(priority: Isolate.immediate);
    }
    _worker = null;
    _isolate = null;
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _shutdownWorker();
  }
}

// Messages. All are sent between isolates, so they hold only sendable data.

class _WorkerStart {
  const _WorkerStart({
    required this.replies,
    required this.modelBytes,
    required this.settings,
    required this.allowedClasses,
    required this.runnerFactory,
    required this.threads,
  });

  final SendPort replies;
  final TransferableTypedData modelBytes;
  final AppSettings settings;
  final Set<int> allowedClasses;
  final ModelRunnerFactory runnerFactory;
  final int threads;
}

class _WorkerReady {
  const _WorkerReady(this.requests, this.accelerator);

  final SendPort requests;
  final String accelerator;
}

class _WorkerFailed {
  const _WorkerFailed(this.error);

  final String error;
}

class _DetectRequest {
  const _DetectRequest(this.id, this.frame);

  final int id;
  final CameraFrame frame;
}

class _DetectReply {
  const _DetectReply(this.id, this.output);

  final int id;
  final DetectionOutput output;
}

class _DetectFailed {
  const _DetectFailed(this.id, this.error);

  final int id;
  final String error;
}

class _Shutdown {
  const _Shutdown();
}

void _workerMain(_WorkerStart start) {
  final ModelRunner runner;
  try {
    runner = start.runnerFactory(
      start.modelBytes.materialize().asUint8List(),
      start.settings.modelInputSize,
      start.threads,
    );
  } catch (error) {
    start.replies.send(_WorkerFailed('$error'));
    Isolate.exit();
  }
  final DetectionEngine engine = DetectionEngine(
    runner: runner,
    settings: start.settings,
    allowedClasses: start.allowedClasses,
  );

  final ReceivePort requests = ReceivePort();
  requests.listen((Object? message) {
    switch (message) {
      case _DetectRequest(:final int id, :final CameraFrame frame):
        try {
          start.replies.send(_DetectReply(id, engine.process(frame)));
        } catch (error) {
          start.replies.send(_DetectFailed(id, '$error'));
        }
      case _Shutdown():
        runner.close();
        requests.close();
    }
  });
  start.replies.send(_WorkerReady(requests.sendPort, runner.accelerator));
}
