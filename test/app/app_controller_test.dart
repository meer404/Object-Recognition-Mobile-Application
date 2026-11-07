import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/app_controller.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/camera/camera_service.dart';

import '../support/fakes.dart';

CameraFrame _frame() => CameraFrame(
  width: 4,
  height: 4,
  format: FrameFormat.bgra8888,
  planes: <FramePlane>[FramePlane(bytes: Uint8List(64), bytesPerRow: 16)],
  timestamp: DateTime.utc(2026),
);

const CameraServiceException _denied = CameraServiceException(
  CameraFailure.permissionDenied,
);

void main() {
  late FakeCameraService camera;
  late FakeHaptics haptics;
  late List<bool> keepAwake;
  late int repeats;
  late int frames;
  late AppController app;

  setUp(() {
    camera = FakeCameraService();
    haptics = FakeHaptics();
    keepAwake = <bool>[];
    repeats = 0;
    frames = 0;
    app = AppController(
      camera: camera,
      haptics: haptics,
      setKeepAwake: (bool on) async => keepAwake.add(on),
      onRepeat: () => repeats++,
      onFrame: (CameraFrame frame) async => frames++,
    );
  });

  /// Runs pending queued operations.
  Future<void> settle() async {
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('start', () {
    test(
      'opens the camera, streams, keeps the screen on, gives haptics',
      () async {
        expect(app.status, AppStatus.initializing);
        await app.start();

        expect(app.status, AppStatus.running);
        expect(camera.calls, <String>['initialize', 'start']);
        expect(keepAwake, <bool>[true]);
        expect(haptics.events, <String>['started']);
        expect(app.showPreview, isTrue);
      },
    );

    test('each failure has its own state and no start haptic', () async {
      final Map<CameraFailure, AppStatus> expected = <CameraFailure, AppStatus>{
        CameraFailure.permissionDenied: AppStatus.permissionDenied,
        CameraFailure.noCamera: AppStatus.noCamera,
        CameraFailure.other: AppStatus.error,
      };
      for (final MapEntry<CameraFailure, AppStatus> e in expected.entries) {
        camera.initializeError = CameraServiceException(e.key);
        await app.start();
        expect(app.status, e.value);
        expect(app.showPreview, isFalse);
      }
      expect(haptics.events, isEmpty);
      expect(keepAwake, isEmpty);
    });

    test('an unexpected exception becomes the error state', () async {
      camera.startError = StateError('boom');
      await app.start();
      expect(app.status, AppStatus.error);
    });
  });

  group('frames', () {
    test('go through the scheduler to the handler', () async {
      await app.start();
      camera.controller.add(_frame());
      await settle();
      expect(frames, 1);
      expect(app.scheduler.acceptedCount, 1);
    });

    test('are rate limited by the scheduler', () async {
      await app.start();
      camera.controller.add(_frame());
      await settle();
      camera.controller.add(_frame());
      await settle();
      expect(frames, 1);
      expect(app.scheduler.droppedRateCount, 1);
    });

    test('settings changes reach the scheduler', () {
      final updated = app.settings.copyWith(targetInferencesPerSecond: 5);
      app.updateSettings(updated);
      expect(app.scheduler.settings, same(updated));
    });
  });

  group('tap', () {
    test('repeats while running', () async {
      await app.start();
      await app.primaryAction();
      expect(repeats, 1);
      expect(haptics.events.last, 'tick');
    });

    test('does nothing while paused', () async {
      await app.start();
      await app.togglePause();
      await app.primaryAction();
      expect(repeats, 0);
      expect(camera.calls.where((String c) => c == 'initialize'), hasLength(1));
    });

    test('retries after a failure', () async {
      camera.initializeError = _denied;
      await app.start();
      expect(app.status, AppStatus.permissionDenied);

      await app.primaryAction();
      expect(app.status, AppStatus.running);
      expect(repeats, 0);
    });
  });

  group('double tap', () {
    test('pauses and resumes with distinct haptics', () async {
      await app.start();
      await app.togglePause();
      expect(app.status, AppStatus.paused);
      expect(camera.streaming, isFalse);
      expect(camera.open, isTrue, reason: 'pause keeps the camera open');
      expect(keepAwake.last, isFalse);
      expect(haptics.events.last, 'stopped');

      await app.togglePause();
      expect(app.status, AppStatus.running);
      expect(camera.streaming, isTrue);
      expect(keepAwake.last, isTrue);
      expect(haptics.events.last, 'started');
    });

    test('is ignored before the camera is running', () async {
      camera.initializeError = _denied;
      await app.start();
      await app.togglePause();
      expect(app.status, AppStatus.permissionDenied);
      expect(camera.calls, isNot(contains('stop')));
    });

    test('a failed resume reports the error', () async {
      await app.start();
      await app.togglePause();
      camera.startError = const CameraServiceException(CameraFailure.other);
      await app.togglePause();
      expect(app.status, AppStatus.error);
    });
  });

  group('app lifecycle', () {
    test('leaving releases the camera, returning restores streaming', () async {
      await app.start();
      bool? cameraOpenWhenPreviewRemoved;
      void watch() {
        if (!app.showPreview) cameraOpenWhenPreviewRemoved ??= camera.open;
      }

      app.addListener(watch);
      app.handleLifecycle(AppLifecycleState.hidden);
      await settle();
      app.removeListener(watch);
      expect(
        cameraOpenWhenPreviewRemoved,
        isTrue,
        reason: 'the preview must go before its camera is released',
      );
      expect(camera.open, isFalse);
      expect(keepAwake.last, isFalse);

      app.handleLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(camera.open, isTrue);
      expect(camera.streaming, isTrue);
      expect(app.status, AppStatus.running);
      expect(app.showPreview, isTrue);
      expect(keepAwake.last, isTrue);
      expect(haptics.events, <String>[
        'started',
      ], reason: 'no haptic on return');
    });

    test('hidden then paused releases only once', () async {
      await app.start();
      app.handleLifecycle(AppLifecycleState.hidden);
      app.handleLifecycle(AppLifecycleState.paused);
      await settle();
      expect(camera.calls.where((String c) => c == 'release'), hasLength(1));
    });

    test('a user pause survives a trip to the background', () async {
      await app.start();
      await app.togglePause();
      app.handleLifecycle(AppLifecycleState.paused);
      await settle();
      app.handleLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(app.status, AppStatus.paused);
      expect(camera.open, isTrue);
      expect(camera.streaming, isFalse);
      expect(app.showPreview, isTrue);
    });

    test('inactive alone does not touch the camera', () async {
      await app.start();
      app.handleLifecycle(AppLifecycleState.inactive);
      app.handleLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(camera.calls, <String>['initialize', 'start']);
    });

    test('denying the dialog does not reopen it in a loop', () async {
      camera.initializeError = _denied;
      // What the permission dialog does: inactive, then resumed on denial.
      app.handleLifecycle(AppLifecycleState.inactive);
      await app.start();
      app.handleLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(app.status, AppStatus.permissionDenied);
      expect(camera.calls, <String>['initialize']);
    });

    test('returning from system settings retries a denied camera', () async {
      camera.initializeError = _denied;
      await app.start();
      app.handleLifecycle(AppLifecycleState.paused);
      await settle();
      app.handleLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(app.status, AppStatus.running);
    });

    test('a camera failure on return is reported', () async {
      await app.start();
      app.handleLifecycle(AppLifecycleState.paused);
      await settle();
      camera.initializeError = const CameraServiceException(
        CameraFailure.other,
      );
      app.handleLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(app.status, AppStatus.error);
    });
  });

  group('detection hooks', () {
    late List<String> events;
    Object? prepareError;

    AppController hooked() => AppController(
      camera: camera,
      haptics: haptics,
      setKeepAwake: (bool on) async {},
      onFrame: (CameraFrame frame) async {},
      prepare: () async {
        events.add('prepare');
        if (prepareError != null) throw prepareError!;
      },
      onStopped: () => events.add('stopped'),
      onDispose: () async => events.add('disposed'),
      onSettingsChanged: (_) => events.add('settings'),
    );

    setUp(() {
      events = <String>[];
      prepareError = null;
    });

    test('prepares before opening the camera', () async {
      final AppController a = hooked();
      await a.start();
      expect(events, <String>['prepare']);
      expect(a.status, AppStatus.running);
    });

    test('a failed prepare is a model error, and no camera opens', () async {
      prepareError = StateError('no model');
      final AppController a = hooked();
      await a.start();
      expect(a.status, AppStatus.modelError);
      expect(camera.calls, isEmpty);
      expect(a.showPreview, isFalse);
    });

    test('a tap retries after a model error', () async {
      prepareError = StateError('no model');
      final AppController a = hooked();
      await a.start();
      prepareError = null;
      await a.primaryAction();
      expect(a.status, AppStatus.running);
    });

    test('pausing and backgrounding tell the pipeline to stop', () async {
      final AppController a = hooked();
      await a.start();
      await a.togglePause();
      expect(events, contains('stopped'));

      events.clear();
      await a.togglePause();
      a.handleLifecycle(AppLifecycleState.paused);
      await settle();
      expect(events, contains('stopped'));
    });

    test('a lost detector stops the camera and is reported', () async {
      final AppController a = hooked();
      await a.start();
      a.reportDetectorLost();
      await settle();
      expect(a.status, AppStatus.modelError);
      expect(camera.streaming, isFalse);
      expect(events, contains('stopped'));
    });

    test('a lost detector is ignored unless running', () async {
      final AppController a = hooked();
      await a.start();
      await a.togglePause();
      a.reportDetectorLost();
      await settle();
      expect(a.status, AppStatus.paused);
    });

    test('settings changes and dispose reach the pipeline', () async {
      final AppController a = hooked();
      await a.start();
      a.updateSettings(a.settings.copyWith(speechVolume: 0.5));
      expect(events, contains('settings'));
      a.dispose();
      await settle();
      expect(events.last, 'disposed');
    });
  });

  group('ordering', () {
    test('overlapping requests never run camera calls at once', () async {
      camera.initializeGate = Completer<void>();
      unawaited(app.start());
      unawaited(app.togglePause());
      app.handleLifecycle(AppLifecycleState.paused);
      app.handleLifecycle(AppLifecycleState.resumed);
      unawaited(app.togglePause());
      await settle();
      camera.initializeGate!.complete();
      await settle();

      expect(camera.maxActive, 1);
      expect(camera.calls.first, 'initialize');
      expect(camera.calls[1], 'start', reason: 'started before anything else');
    });

    test('dispose releases the camera after work in progress', () async {
      camera.initializeGate = Completer<void>();
      unawaited(app.start());
      await settle();
      app.dispose();
      camera.initializeGate!.complete();
      await settle();

      expect(camera.calls.last, 'dispose');
      expect(keepAwake, contains(false));
    });
  });
}
