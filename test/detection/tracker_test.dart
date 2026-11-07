import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/detection/detection_filter.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/detection/tracker.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

TrackedDetection _object(
  int id, {
  HorizontalPosition position = HorizontalPosition.center,
}) => TrackedDetection(
  trackId: id,
  detection: DetectionResult(
    classId: 56,
    confidence: 0.9,
    box: const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2),
    position: position,
  ),
);

FilterResult _result(List<TrackedDetection> confirmed, {Set<int>? live}) =>
    FilterResult(
      confirmed: confirmed,
      liveTrackIds:
          live ?? <int>{for (final TrackedDetection o in confirmed) o.trackId},
    );

void main() {
  final DateTime start = DateTime.utc(2026);
  late Tracker tracker;

  setUp(() => tracker = Tracker(settings: const AppSettings()));

  test('a new object is due', () {
    expect(
      tracker.objectsToAnnounce(_result(<TrackedDetection>[_object(1)]), start),
      hasLength(1),
    );
  });

  test('asking does not consume: it stays due until marked announced', () {
    final FilterResult r = _result(<TrackedDetection>[_object(1)]);
    tracker.objectsToAnnounce(r, start);
    expect(tracker.objectsToAnnounce(r, start), hasLength(1));
  });

  test('once announced it is not repeated within the cooldown', () {
    final FilterResult r = _result(<TrackedDetection>[_object(1)]);
    tracker.markAnnounced(tracker.objectsToAnnounce(r, start), start);
    expect(
      tracker.objectsToAnnounce(
        r,
        start.add(const Duration(milliseconds: 4999)),
      ),
      isEmpty,
    );
  });

  test('it is repeated once the cooldown has expired', () {
    final FilterResult r = _result(<TrackedDetection>[_object(1)]);
    tracker.markAnnounced(tracker.objectsToAnnounce(r, start), start);
    expect(
      tracker.objectsToAnnounce(r, start.add(const Duration(seconds: 5))),
      hasLength(1),
    );
  });

  test('announcing again restarts the cooldown', () {
    final FilterResult r = _result(<TrackedDetection>[_object(1)]);
    tracker.markAnnounced(r.confirmed, start);
    final DateTime later = start.add(const Duration(seconds: 5));
    tracker.markAnnounced(tracker.objectsToAnnounce(r, later), later);
    expect(
      tracker.objectsToAnnounce(r, later.add(const Duration(seconds: 1))),
      isEmpty,
    );
  });

  test('a position change is due at once', () {
    tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
    expect(
      tracker.objectsToAnnounce(
        _result(<TrackedDetection>[
          _object(1, position: HorizontalPosition.left),
        ]),
        start.add(const Duration(seconds: 1)),
      ),
      hasLength(1),
    );
  });

  test('moving back again is another change', () {
    tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
    tracker.markAnnounced(<TrackedDetection>[
      _object(1, position: HorizontalPosition.left),
    ], start);
    expect(
      tracker.objectsToAnnounce(_result(<TrackedDetection>[_object(1)]), start),
      hasLength(1),
    );
  });

  test('a returning object (new track) is due at once', () {
    tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
    expect(
      tracker.objectsToAnnounce(
        _result(<TrackedDetection>[_object(2)]),
        start.add(const Duration(seconds: 1)),
      ),
      hasLength(1),
    );
  });

  test(
    'flicker: temporarily unconfirmed but still live is not re-announced',
    () {
      tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
      final DateTime t = start.add(const Duration(seconds: 1));
      // Dropped below N of M, but its track is still in the window.
      tracker.objectsToAnnounce(
        _result(<TrackedDetection>[], live: <int>{1}),
        t,
      );
      expect(
        tracker.objectsToAnnounce(_result(<TrackedDetection>[_object(1)]), t),
        isEmpty,
        reason: 'must not bypass the cooldown',
      );
    },
  );

  test('state for tracks that have gone is dropped', () {
    tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
    tracker.objectsToAnnounce(_result(<TrackedDetection>[]), start);
    // The same id could only come back as new; it must count as new.
    expect(
      tracker.objectsToAnnounce(_result(<TrackedDetection>[_object(1)]), start),
      hasLength(1),
    );
  });

  test('only due objects are returned', () {
    tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
    final List<TrackedDetection> due = tracker.objectsToAnnounce(
      _result(<TrackedDetection>[_object(1), _object(2)]),
      start,
    );
    expect(due.single.trackId, 2);
  });

  test('reset makes everything due again', () {
    tracker.markAnnounced(<TrackedDetection>[_object(1)], start);
    tracker.reset();
    expect(
      tracker.objectsToAnnounce(_result(<TrackedDetection>[_object(1)]), start),
      hasLength(1),
    );
  });
}
