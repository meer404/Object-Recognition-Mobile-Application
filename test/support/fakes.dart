import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kurdish_vision/accessibility/haptics.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/camera/camera_service.dart';

/// Scriptable camera. `calls` records the order of operations.
class FakeCameraService implements CameraService {
  final StreamController<CameraFrame> controller =
      StreamController<CameraFrame>.broadcast(sync: true);
  final List<String> calls = <String>[];

  /// Thrown by the next initialize(), then cleared.
  Object? initializeError;

  /// Thrown by the next start(), then cleared.
  Object? startError;

  /// Thrown by the next stop(), then cleared.
  Object? stopError;

  /// While set, initialize() waits for it, to test overlapping operations.
  Completer<void>? initializeGate;

  bool open = false;
  bool streaming = false;
  int active = 0;
  int maxActive = 0;

  Future<void> _run(String name, Future<void> Function() body) async {
    calls.add(name);
    active++;
    maxActive = active > maxActive ? active : maxActive;
    try {
      // A microtask, not a timer: async like a real camera, but it also runs
      // under the widget tester's fake clock.
      await Future<void>.value();
      await body();
    } finally {
      active--;
    }
  }

  @override
  Stream<CameraFrame> get frames => controller.stream;

  @override
  bool get isStreaming => streaming;

  @override
  Future<void> initialize() => _run('initialize', () async {
    await initializeGate?.future;
    final Object? error = initializeError;
    initializeError = null;
    if (error != null) throw error;
    open = true;
  });

  @override
  Future<void> start() => _run('start', () async {
    final Object? error = startError;
    startError = null;
    if (error != null) throw error;
    streaming = true;
  });

  @override
  Future<void> stop() => _run('stop', () async {
    final Object? error = stopError;
    stopError = null;
    if (error != null) throw error;
    streaming = false;
  });

  @override
  Future<void> release() => _run('release', () async {
    streaming = false;
    open = false;
  });

  @override
  Widget buildPreview() => const SizedBox.expand(key: Key('fake-preview'));

  @override
  Future<void> dispose() => _run('dispose', () async {
    streaming = false;
    open = false;
    await controller.close();
  });
}

class FakeHaptics implements Haptics {
  final List<String> events = <String>[];

  @override
  Future<void> started() async => events.add('started');

  @override
  Future<void> stopped() async => events.add('stopped');

  @override
  Future<void> tick() async => events.add('tick');
}
