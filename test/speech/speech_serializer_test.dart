import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/speech/speech_serializer.dart';
import 'package:kurdish_vision/speech/speech_service.dart';

/// Lets a test drive each performance: start it, finish it, or fail it.
class _Performance {
  _Performance(this.item, this.onStarted);
  final String item;
  final void Function() onStarted;
  final Completer<void> done = Completer<void>();

  void start() => onStarted();
  void finish() {
    if (!done.isCompleted) done.complete();
  }
}

class _Harness {
  _Harness() {
    serializer = SpeechSerializer<String>(
      perform: (String item, void Function() onStarted) {
        final _Performance p = _Performance(item, onStarted);
        performances.add(p);
        active++;
        maxActive = active > maxActive ? active : maxActive;
        return p.done.future.whenComplete(() => active--);
      },
      stopCurrent: () async {
        stopCalls++;
        for (final _Performance p in performances) {
          p.finish();
        }
      },
      onError: (Object e, StackTrace s) => errors.add(e),
    );
    subscription = serializer.isSpeaking.listen(speakingEvents.add);
  }

  late final SpeechSerializer<String> serializer;
  late final StreamSubscription<bool> subscription;
  final List<_Performance> performances = <_Performance>[];
  final List<bool> speakingEvents = <bool>[];
  final List<Object> errors = <Object>[];
  int active = 0;
  int maxActive = 0;
  int stopCalls = 0;

  List<String> get performed => <String>[
    for (final _Performance p in performances) p.item,
  ];

  Future<void> dispose() async {
    await subscription.cancel();
    await serializer.dispose();
  }
}

/// Lets queued microtasks and `then` callbacks run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  test('idle submit plays immediately and completes on start', () async {
    final Future<SpeechOutcome> outcome = h.serializer.submit('a');
    expect(h.performed, <String>['a']);
    expect(h.serializer.speaking, isTrue);

    h.performances.single.start();
    expect(await outcome, SpeechOutcome.started);

    h.performances.single.finish();
    await settle();
    expect(h.serializer.speaking, isFalse);
    expect(h.speakingEvents, <bool>[true, false]);
  });

  test('a request submitted while busy waits for the current one', () async {
    unawaited(h.serializer.submit('a'));
    h.performances[0].start();
    final Future<SpeechOutcome> b = h.serializer.submit('b');

    await settle();
    expect(h.performed, <String>['a'], reason: 'b must not overlap a');

    h.performances[0].finish();
    await settle();
    expect(h.performed, <String>['a', 'b']);
    h.performances[1].start();
    expect(await b, SpeechOutcome.started);
    expect(h.maxActive, 1);
  });

  test('only the newest waiting request survives', () async {
    unawaited(h.serializer.submit('a'));
    final Future<SpeechOutcome> b = h.serializer.submit('b');
    final Future<SpeechOutcome> c = h.serializer.submit('c');
    final Future<SpeechOutcome> d = h.serializer.submit('d');

    expect(await b, SpeechOutcome.dropped);
    expect(await c, SpeechOutcome.dropped);

    h.performances[0].finish();
    await settle();
    expect(h.performed, <String>['a', 'd']);
    h.performances[1].start();
    expect(await d, SpeechOutcome.started);
    expect(h.maxActive, 1);
  });

  test('speaking stays true across back-to-back items', () async {
    unawaited(h.serializer.submit('a'));
    unawaited(h.serializer.submit('b'));
    h.performances[0].finish();
    await settle();
    h.performances[1].finish();
    await settle();
    expect(h.speakingEvents, <bool>[true, false]);
  });

  test('interrupt cuts current speech and plays the new item next', () async {
    final Future<SpeechOutcome> a = h.serializer.submit('a');
    h.performances[0].start();
    final Future<SpeechOutcome> r = h.serializer.submit('r', interrupt: true);

    await settle();
    expect(h.stopCalls, 1);
    expect(await a, SpeechOutcome.started, reason: 'a had already started');
    expect(h.performed, <String>['a', 'r']);
    h.performances[1].start();
    expect(await r, SpeechOutcome.started);
    expect(h.maxActive, 1);
  });

  test('stop drops the waiting item and goes idle', () async {
    unawaited(h.serializer.submit('a'));
    h.performances[0].start();
    final Future<SpeechOutcome> b = h.serializer.submit('b');

    await h.serializer.stop();
    await settle();

    expect(await b, SpeechOutcome.dropped);
    expect(h.performed, <String>['a']);
    expect(h.serializer.speaking, isFalse);
    expect(h.speakingEvents.last, isFalse);
  });

  test('stopping before audio starts reports dropped', () async {
    final Future<SpeechOutcome> a = h.serializer.submit('a');
    await h.serializer.stop();
    expect(await a, SpeechOutcome.dropped);
  });

  test('ending without starting reports failed', () async {
    final Future<SpeechOutcome> a = h.serializer.submit('a');
    h.performances[0].finish();
    expect(await a, SpeechOutcome.failed);
  });

  test('a throwing performer fails and the next item still plays', () async {
    final SpeechSerializer<String> s = SpeechSerializer<String>(
      perform: (String item, void Function() onStarted) async {
        if (item == 'bad') throw StateError('boom');
        onStarted();
      },
      stopCurrent: () async {},
      onError: (Object e, StackTrace st) => h.errors.add(e),
    );
    final Future<SpeechOutcome> bad = s.submit('bad');
    final Future<SpeechOutcome> good = s.submit('good');

    expect(await bad, SpeechOutcome.failed);
    expect(await good, SpeechOutcome.started);
    expect(h.errors.single, isA<StateError>());
    await s.dispose();
  });

  test('submit after dispose is dropped', () async {
    await h.serializer.dispose();
    expect(await h.serializer.submit('x'), SpeechOutcome.dropped);
    expect(h.performed, isEmpty);
  });
}
