import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../accessibility/haptics.dart';
import '../camera/camera_frame.dart';
import '../camera/camera_service.dart';
import '../camera/frame_scheduler.dart';
import '../settings/app_settings.dart';

/// High-level app state.
enum AppStatus {
  initializing,
  running,
  paused,
  permissionDenied,
  noCamera,
  error,
}

/// Orchestrates the pipeline:
/// CameraStream → FrameScheduler → Detector → DetectionFilter & Tracker
/// → PhraseBuilder → SpeechOutput.
///
/// Phase 2 covers the camera and user controls. [onFrame] and [onRepeat] are
/// where Phase 3 connects detection and speech.
class AppController extends ChangeNotifier {
  AppController({
    required CameraService camera,
    required FrameHandler onFrame,
    required Haptics haptics,
    required Future<void> Function(bool enabled) setKeepAwake,
    AppSettings settings = const AppSettings(),
    MonotonicClock? clock,
    VoidCallback? onRepeat,
  }) : _camera = camera,
       _haptics = haptics,
       _setKeepAwake = setKeepAwake,
       _onRepeat = onRepeat,
       _settings = settings {
    scheduler = FrameScheduler(
      settings: settings,
      onFrame: onFrame,
      clock: clock,
    );
    _frames = camera.frames.listen(scheduler.offer);
  }

  final CameraService _camera;
  final Haptics _haptics;
  final Future<void> Function(bool enabled) _setKeepAwake;
  final VoidCallback? _onRepeat;

  late final FrameScheduler scheduler;
  late final StreamSubscription<CameraFrame> _frames;

  /// Camera calls run strictly one at a time, in the order requested.
  Future<void> _queue = Future<void>.value();

  AppSettings _settings;
  AppStatus _status = AppStatus.initializing;
  bool _backgrounded = false;
  bool _cameraReleased = false;
  bool _disposed = false;

  AppSettings get settings => _settings;
  AppStatus get status => _status;

  /// Whether the camera preview can be shown right now.
  bool get showPreview =>
      !_cameraReleased &&
      (_status == AppStatus.running || _status == AppStatus.paused);

  /// The camera service, for building the preview.
  CameraService get camera => _camera;

  void updateSettings(AppSettings value) {
    _settings = value;
    scheduler.settings = value;
    notifyListeners();
  }

  /// Opens the camera and starts streaming.
  Future<void> start() => _enqueue(() => _open(announceStart: true));

  /// The whole-screen single tap: repeat while running, retry after a failure.
  Future<void> primaryAction() async {
    switch (_status) {
      case AppStatus.running:
        _onRepeat?.call();
        await _haptics.tick();
      case AppStatus.permissionDenied:
      case AppStatus.noCamera:
      case AppStatus.error:
        await start();
      case AppStatus.initializing:
      case AppStatus.paused:
        break;
    }
  }

  /// The double tap: pause or resume. Ignored in any other state.
  Future<void> togglePause() => _enqueue(() async {
    if (_status == AppStatus.running) {
      await _camera.stop();
      await _setKeepAwake(false);
      _setStatus(AppStatus.paused);
      await _haptics.stopped();
    } else if (_status == AppStatus.paused) {
      await _startStreaming(announceStart: true);
    }
  });

  /// Releases the camera when the app leaves the screen and restores it on
  /// return. `inactive` is deliberately ignored: the permission dialog and
  /// multi-window focus changes cause it while the app is still visible.
  void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _backgrounded = true;
        unawaited(_enqueue(_suspend));
      case AppLifecycleState.resumed:
        // Only after a real trip to the background. Denying the permission
        // dialog also fires `resumed`, and retrying then would reopen the
        // dialog immediately, forever.
        if (_backgrounded) {
          _backgrounded = false;
          unawaited(_enqueue(_restore));
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _open({required bool announceStart}) async {
    _cameraReleased = false;
    _setStatus(AppStatus.initializing);
    await _guarded(() async {
      await _camera.initialize();
      await _startStreaming(announceStart: announceStart);
    });
  }

  Future<void> _startStreaming({required bool announceStart}) async {
    await _guarded(() async {
      await _camera.start();
      scheduler.resetRateLimit();
      await _setKeepAwake(true);
      _setStatus(AppStatus.running);
      if (announceStart) await _haptics.started();
    });
  }

  Future<void> _suspend() async {
    if (_cameraReleased) return;
    if (_status != AppStatus.running && _status != AppStatus.paused) return;
    _cameraReleased = true;
    notifyListeners(); // Removes the preview before its controller goes away.
    await _guarded(() async {
      await _setKeepAwake(false);
      await _camera.release();
    });
  }

  Future<void> _restore() async {
    switch (_status) {
      case AppStatus.running:
      case AppStatus.paused:
        if (!_cameraReleased) return;
        final bool wasRunning = _status == AppStatus.running;
        _cameraReleased = false;
        await _guarded(() async {
          await _camera.initialize();
          if (wasRunning) {
            await _startStreaming(announceStart: false);
          } else {
            notifyListeners(); // Shows the preview again, still paused.
          }
        });
      case AppStatus.permissionDenied:
      case AppStatus.noCamera:
      case AppStatus.error:
        // The user may have just granted permission in the system settings.
        await _open(announceStart: true);
      case AppStatus.initializing:
        break;
    }
  }

  Future<void> _guarded(Future<void> Function() operation) async {
    try {
      await operation();
    } on CameraServiceException catch (e) {
      developer.log('camera failure: $e', name: 'app');
      _setStatus(switch (e.failure) {
        CameraFailure.permissionDenied => AppStatus.permissionDenied,
        CameraFailure.noCamera => AppStatus.noCamera,
        CameraFailure.other => AppStatus.error,
      });
    } catch (error, stackTrace) {
      developer.log(
        'camera operation failed',
        name: 'app',
        error: error,
        stackTrace: stackTrace,
      );
      _setStatus(AppStatus.error);
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    return _queue = _queue.then((_) => _disposed ? null : operation());
  }

  void _setStatus(AppStatus value) {
    if (value == _status || _disposed) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_frames.cancel());
    unawaited(_setKeepAwake(false));
    // Runs after any operation already in progress.
    unawaited(_queue.then((_) => _camera.dispose()));
    super.dispose();
  }
}
