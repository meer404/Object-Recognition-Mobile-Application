import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/detection/detection_filter.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

const AppSettings _settings = AppSettings();

DetectionResult _det({
  int classId = 56,
  double confidence = 0.9,
  double x = 0.5,
  double y = 0.5,
  double size = 0.2,
}) => DetectionResult(
  classId: classId,
  confidence: confidence,
  box: Rect.fromCenter(center: Offset(x, y), width: size, height: size),
  position: HorizontalPosition.fromCenterX(x, _settings),
);

void main() {
  late DetectionFilter filter;

  setUp(() => filter = DetectionFilter(settings: _settings));

  group('N of M confirmation (2 of 3)', () {
    test('one sighting is not enough', () {
      expect(filter.update(<DetectionResult>[_det()]).confirmed, isEmpty);
    });

    test('two in a row confirms', () {
      filter.update(<DetectionResult>[_det()]);
      expect(filter.update(<DetectionResult>[_det()]).confirmed, hasLength(1));
    });

    test('hit, miss, hit confirms', () {
      filter.update(<DetectionResult>[_det()]);
      filter.update(<DetectionResult>[]);
      expect(filter.update(<DetectionResult>[_det()]).confirmed, hasLength(1));
    });

    test('hit, miss, miss, hit does not: the window has moved on', () {
      filter.update(<DetectionResult>[_det()]);
      filter.update(<DetectionResult>[]);
      filter.update(<DetectionResult>[]);
      expect(filter.update(<DetectionResult>[_det()]).confirmed, isEmpty);
    });

    test('a single miss keeps the object confirmed, with its last box', () {
      filter.update(<DetectionResult>[_det()]);
      filter.update(<DetectionResult>[_det(x: 0.5)]);
      final FilterResult result = filter.update(<DetectionResult>[]);
      expect(result.confirmed, hasLength(1));
      expect(result.confirmed.single.detection.box.center.dx, closeTo(0.5, 1e-9));
    });

    test('respects other N and M settings', () {
      final DetectionFilter strict = DetectionFilter(
        settings: const AppSettings(confirmationHits: 3, confirmationWindow: 3),
      );
      strict.update(<DetectionResult>[_det()]);
      strict.update(<DetectionResult>[_det()]);
      expect(strict.update(<DetectionResult>[]).confirmed, isEmpty);

      final DetectionFilter instant = DetectionFilter(
        settings: const AppSettings(confirmationHits: 1, confirmationWindow: 1),
      );
      expect(instant.update(<DetectionResult>[_det()]).confirmed, hasLength(1));
    });
  });

  group('confidence threshold', () {
    test('results below it count as misses', () {
      filter.update(<DetectionResult>[_det(confidence: 0.49)]);
      expect(
        filter.update(<DetectionResult>[_det(confidence: 0.49)]).confirmed,
        isEmpty,
      );
    });

    test('a result exactly at it counts', () {
      filter.update(<DetectionResult>[_det(confidence: 0.5)]);
      expect(
        filter.update(<DetectionResult>[_det(confidence: 0.5)]).confirmed,
        hasLength(1),
      );
    });
  });

  group('tracks', () {
    test('a moving object keeps its track', () {
      filter.update(<DetectionResult>[_det(x: 0.5)]);
      final int id = filter
          .update(<DetectionResult>[_det(x: 0.52)])
          .confirmed
          .single
          .trackId;
      expect(
        filter.update(<DetectionResult>[_det(x: 0.54)]).confirmed.single.trackId,
        id,
      );
    });

    test('two objects of one class are tracked separately', () {
      final List<DetectionResult> both = <DetectionResult>[
        _det(x: 0.2),
        _det(x: 0.8),
      ];
      filter.update(both);
      final FilterResult result = filter.update(both);
      expect(result.confirmed, hasLength(2));
      expect(
        result.confirmed.map((TrackedDetection t) => t.trackId).toSet(),
        hasLength(2),
      );
    });

    test('different classes never share a track', () {
      filter.update(<DetectionResult>[_det(classId: 56)]);
      expect(filter.update(<DetectionResult>[_det(classId: 60)]).confirmed, isEmpty);
    });

    test('a jump with no overlap starts a new track', () {
      filter.update(<DetectionResult>[_det(x: 0.2)]);
      expect(filter.update(<DetectionResult>[_det(x: 0.8)]).confirmed, isEmpty);
    });

    test('the best overlap wins when a detection could match two tracks', () {
      filter.update(<DetectionResult>[_det(x: 0.4), _det(x: 0.6)]);
      final FilterResult r = filter.update(<DetectionResult>[
        _det(x: 0.41),
        _det(x: 0.59),
      ]);
      expect(r.confirmed, hasLength(2));
      expect(r.liveTrackIds, hasLength(2), reason: 'no extra tracks');
    });

    test('a track stays live until its whole window is empty', () {
      filter.update(<DetectionResult>[_det()]);
      final int id = filter.update(<DetectionResult>[_det()]).confirmed.single.trackId;
      filter.update(<DetectionResult>[]);
      expect(filter.update(<DetectionResult>[]).liveTrackIds, contains(id));
      expect(filter.update(<DetectionResult>[]).liveTrackIds, isEmpty);
    });

    test('an object that came back gets a new track id', () {
      filter.update(<DetectionResult>[_det()]);
      final int first = filter.update(<DetectionResult>[_det()]).confirmed.single.trackId;
      for (int i = 0; i < 3; i++) {
        filter.update(<DetectionResult>[]);
      }
      filter.update(<DetectionResult>[_det()]);
      expect(
        filter.update(<DetectionResult>[_det()]).confirmed.single.trackId,
        isNot(first),
      );
    });

    test('reset forgets everything', () {
      filter.update(<DetectionResult>[_det()]);
      filter.reset();
      expect(filter.update(<DetectionResult>[_det()]).confirmed, isEmpty);
    });
  });

  group('position hysteresis', () {
    HorizontalPosition positionAfter(List<double> xs) {
      late FilterResult result;
      // A wide box, so small moves stay on one track.
      for (final double x in xs) {
        result = filter.update(<DetectionResult>[_det(x: x, size: 0.5)]);
      }
      return result.confirmed.single.detection.position;
    }

    test('a centre just past a boundary keeps its position', () {
      expect(
        positionAfter(<double>[0.5, 0.5, 0.65, 0.69]),
        HorizontalPosition.center,
      );
    });

    test('flickering around a boundary does not flip the position', () {
      expect(
        positionAfter(<double>[0.5, 0.5, 0.68, 0.65, 0.68, 0.65]),
        HorizontalPosition.center,
      );
    });

    test('clearly crossing a boundary changes it', () {
      expect(
        positionAfter(<double>[0.5, 0.5, 0.6, 0.72]),
        HorizontalPosition.right,
      );
    });
  });
}
