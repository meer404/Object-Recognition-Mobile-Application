import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/camera/frame_scheduler.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

CameraFrame _frame() => CameraFrame(
  width: 4,
  height: 4,
  format: FrameFormat.bgra8888,
  planes: <FramePlane>[FramePlane(bytes: Uint8List(64), bytesPerRow: 16)],
  timestamp: DateTime.utc(2026),
);

/// Lets queued microtasks and `then` callbacks run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Duration now;
  late List<Completer<void>> running;
  late List<Object> errors;
  late FrameScheduler scheduler;

  setUp(() {
    now = Duration.zero;
    running = <Completer<void>>[];
    errors = <Object>[];
    scheduler = FrameScheduler(
      // 4 per second = one every 250 ms.
      settings: const AppSettings(targetInferencesPerSecond: 4),
      clock: () => now,
      onError: (Object e, StackTrace s) => errors.add(e),
      onFrame: (CameraFrame frame) {
        final Completer<void> done = Completer<void>();
        running.add(done);
        return done.future;
      },
    );
  });

  Future<void> finishLast() async {
    running.last.complete();
    await settle();
  }

  test('the first frame is accepted and starts at once', () {
    expect(scheduler.offer(_frame()), FrameDecision.accepted);
    expect(running, hasLength(1));
    expect(scheduler.isBusy, isTrue);
  });

  test('frames are dropped while busy, never queued', () async {
    scheduler.offer(_frame());
    now = const Duration(seconds: 10);
    expect(scheduler.offer(_frame()), FrameDecision.droppedBusy);
    expect(scheduler.offer(_frame()), FrameDecision.droppedBusy);

    await finishLast();
    expect(scheduler.isBusy, isFalse);
    expect(running, hasLength(1), reason: 'dropped frames must not run later');
  });

  test('frames arriving too soon are dropped', () async {
    scheduler.offer(_frame());
    await finishLast();

    now = const Duration(milliseconds: 249);
    expect(scheduler.offer(_frame()), FrameDecision.droppedRate);
    expect(running, hasLength(1));
  });

  test('a frame exactly one interval later is accepted', () async {
    scheduler.offer(_frame());
    await finishLast();

    now = const Duration(milliseconds: 250);
    expect(scheduler.offer(_frame()), FrameDecision.accepted);
    expect(running, hasLength(2));
  });

  test('the interval runs from the start of the last accepted frame', () async {
    scheduler.offer(_frame());
    now = const Duration(milliseconds: 300);
    await finishLast();
    expect(
      scheduler.offer(_frame()),
      FrameDecision.accepted,
      reason: 'a slow inference must not add a further wait',
    );
  });

  test('dropped frames do not delay the next accepted one', () async {
    scheduler.offer(_frame());
    await finishLast();
    now = const Duration(milliseconds: 200);
    scheduler.offer(_frame());
    now = const Duration(milliseconds: 250);
    expect(scheduler.offer(_frame()), FrameDecision.accepted);
  });

  test('never exceeds the target rate on a 30 fps stream', () async {
    const Duration frameGap = Duration(microseconds: 33333);
    for (int i = 0; i < 300; i++) {
      now = frameGap * i;
      if (scheduler.offer(_frame()) == FrameDecision.accepted) {
        await finishLast();
      }
    }
    // Frames only arrive every 33.3 ms, so the first one at least 250 ms after
    // the last is every 8th (266.7 ms): 3.75 per second, not 4. Over 300
    // frames that is 38 accepted (D-016).
    expect(scheduler.acceptedCount, 38);
    expect(
      scheduler.acceptedCount + scheduler.droppedRateCount,
      300,
      reason: 'every frame is counted once',
    );
  });

  test('counters record each kind of decision', () async {
    scheduler.offer(_frame());
    scheduler.offer(_frame());
    await finishLast();
    scheduler.offer(_frame());
    expect(scheduler.acceptedCount, 1);
    expect(scheduler.droppedBusyCount, 1);
    expect(scheduler.droppedRateCount, 1);
  });

  test('a failed inference is reported and frees the scheduler', () async {
    scheduler.offer(_frame());
    running.last.completeError(StateError('boom'));
    await settle();

    expect(errors.single, isA<StateError>());
    expect(scheduler.isBusy, isFalse);
    now = const Duration(seconds: 1);
    expect(scheduler.offer(_frame()), FrameDecision.accepted);
  });

  test('a handler that throws synchronously also frees it', () async {
    final FrameScheduler throwing = FrameScheduler(
      settings: const AppSettings(),
      clock: () => now,
      onError: (Object e, StackTrace s) => errors.add(e),
      onFrame: (CameraFrame frame) => throw StateError('sync'),
    );
    expect(throwing.offer(_frame()), FrameDecision.accepted);
    await settle();
    expect(errors.single, isA<StateError>());
    expect(throwing.isBusy, isFalse);
  });

  test('a changed rate applies from the next frame', () async {
    scheduler.offer(_frame());
    await finishLast();
    scheduler.settings = const AppSettings(targetInferencesPerSecond: 5);

    now = const Duration(milliseconds: 200);
    expect(scheduler.offer(_frame()), FrameDecision.accepted);
  });

  test('resetRateLimit allows a frame at once, unless busy', () async {
    scheduler.offer(_frame());
    scheduler.resetRateLimit();
    expect(scheduler.offer(_frame()), FrameDecision.droppedBusy);

    await finishLast();
    scheduler.resetRateLimit();
    expect(scheduler.offer(_frame()), FrameDecision.accepted);
  });
}
