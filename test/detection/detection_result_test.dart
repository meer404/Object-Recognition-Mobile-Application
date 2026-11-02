import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/settings/app_settings.dart';
import 'package:kurdish_vision/speech/kurdish_labels.dart';

void main() {
  const AppSettings settings = AppSettings();

  group('HorizontalPosition.fromCenterX', () {
    test('classifies the three regions', () {
      expect(
        HorizontalPosition.fromCenterX(0.1, settings),
        HorizontalPosition.left,
      );
      expect(
        HorizontalPosition.fromCenterX(0.5, settings),
        HorizontalPosition.center,
      );
      expect(
        HorizontalPosition.fromCenterX(0.9, settings),
        HorizontalPosition.right,
      );
    });

    test('boundaries: left end is center, right start is right', () {
      expect(
        HorizontalPosition.fromCenterX(settings.leftRegionEnd, settings),
        HorizontalPosition.center,
      );
      expect(
        HorizontalPosition.fromCenterX(settings.rightRegionStart, settings),
        HorizontalPosition.right,
      );
    });
  });

  test('priority is confidence × box area', () {
    const DetectionResult d = DetectionResult(
      classId: 0,
      confidence: 0.8,
      box: Rect.fromLTWH(0, 0, 0.5, 0.5),
      position: HorizontalPosition.center,
    );
    expect(d.relativeArea, closeTo(0.25, 1e-9));
    expect(d.priority, closeTo(0.2, 1e-9));
  });

  test('every position has a Sorani phrase', () {
    for (final HorizontalPosition p in HorizontalPosition.values) {
      expect(positionPhrases[p], isNotNull);
    }
  });
}
