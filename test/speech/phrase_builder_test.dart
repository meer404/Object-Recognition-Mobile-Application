import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/settings/app_settings.dart';
import 'package:kurdish_vision/speech/kurdish_labels.dart';
import 'package:kurdish_vision/speech/phrase_builder.dart';

const int _table = 60;
const int _cup = 41;
const int _chair = 56;
const int _book = 73;

/// [size] sets the box area, so tests control the order.
DetectionResult _det(
  int classId, {
  double size = 0.5,
  double confidence = 0.9,
  HorizontalPosition position = HorizontalPosition.center,
}) => DetectionResult(
  classId: classId,
  confidence: confidence,
  box: Rect.fromLTWH(0, 0, size, size),
  position: position,
);

void main() {
  final PhraseBuilder builder = PhraseBuilder(settings: const AppSettings());

  group('sentences', () {
    test('one object in front (CLAUDE.md template)', () {
      final Phrase p = builder.build(<DetectionResult>[_det(_table)])!;
      expect(p.request.text, 'لەبەردەمت مێزێک هەیە.');
      expect(p.request.clipKeys, <String>['in_front', 'class_60', 'exists']);
      expect(p.classes, <int>{_table});
    });

    test('the main object says where it is', () {
      expect(
        builder
            .build(<DetectionResult>[
              _det(_table, position: HorizontalPosition.left),
            ])!
            .request
            .text,
        'لای چەپ مێزێک هەیە.',
      );
      final Phrase right = builder.build(<DetectionResult>[
        _det(_table, position: HorizontalPosition.right),
      ])!;
      expect(right.request.text, 'لای ڕاست مێزێک هەیە.');
      expect(right.request.clipKeys.first, 'on_right');
    });

    test('two objects use «ـیش» and the singular verb', () {
      final Phrase p = builder.build(<DetectionResult>[
        _det(_table, size: 0.8),
        _det(_cup, size: 0.3),
      ])!;
      expect(p.request.text, 'لەبەردەمت مێزێک هەیە. پەرداخێکیش دەبینرێت.');
      expect(p.request.clipKeys, <String>[
        'in_front',
        'class_60',
        'exists',
        'class_41_also',
        'seen_one',
      ]);
    });

    test('three objects match the CLAUDE.md example', () {
      final Phrase p = builder.build(<DetectionResult>[
        _det(_table, size: 0.8),
        _det(_cup, size: 0.5),
        _det(_chair, size: 0.3),
      ])!;
      expect(
        p.request.text,
        'لەبەردەمت مێزێک هەیە. پەرداخێک و کورسییەکیش دەبینرێن.',
      );
      expect(p.request.clipKeys, <String>[
        'in_front',
        'class_60',
        'exists',
        'class_41',
        'and',
        'class_56_also',
        'seen_many',
      ]);
    });
  });

  group('selection', () {
    test('at most 3 objects, dropping the lowest priority', () {
      final Phrase p = builder.build(<DetectionResult>[
        _det(_book, size: 0.1),
        _det(_table, size: 0.8),
        _det(_cup, size: 0.5),
        _det(_chair, size: 0.3),
      ])!;
      expect(p.classes, <int>{_table, _cup, _chair});
      expect(p.request.clipKeys, isNot(contains('class_73')));
    });

    test('the limit is configurable', () {
      final Phrase p = PhraseBuilder(
        settings: const AppSettings(maxObjectsPerSentence: 1),
      ).build(<DetectionResult>[_det(_table), _det(_cup, size: 0.1)])!;
      expect(p.request.text, 'لەبەردەمت مێزێک هەیە.');
      expect(p.classes, <int>{_table});
    });

    test('orders by confidence × box size, not either alone', () {
      // Large but unsure (0.6 × 0.25 = 0.15) vs small but sure (0.9 × 0.09 = 0.08).
      final Phrase p = builder.build(<DetectionResult>[
        _det(_cup, size: 0.3, confidence: 0.9),
        _det(_table, size: 0.5, confidence: 0.6),
      ])!;
      expect(p.request.clipKeys[1], 'class_60');
    });

    test('names a class once, and the free slot goes to another class', () {
      final Phrase p = builder.build(<DetectionResult>[
        _det(_chair, size: 0.8),
        _det(_chair, size: 0.7),
        _det(_chair, size: 0.6),
        _det(_cup, size: 0.2),
      ])!;
      expect(p.request.text, 'لەبەردەمت کورسییەک هەیە. پەرداخێکیش دەبینرێت.');
      expect(p.classes, <int>{_chair, _cup});
    });

    test('a class without a label is never spoken', () {
      expect(kurdishLabels.containsKey(5), isFalse, reason: 'bus');
      expect(builder.build(<DetectionResult>[_det(5)]), isNull);
      expect(
        builder
            .build(<DetectionResult>[_det(5, size: 0.9), _det(_cup, size: 0.1)])!
            .classes,
        <int>{_cup},
      );
    });

    test('nothing to say gives null', () {
      expect(builder.build(<DetectionResult>[]), isNull);
    });
  });

  group('requests', () {
    test('interrupt is passed through and off by default', () {
      final List<DetectionResult> one = <DetectionResult>[_det(_table)];
      expect(builder.build(one)!.request.interrupt, isFalse);
      expect(builder.build(one, interrupt: true)!.request.interrupt, isTrue);
    });

    test('nothingDetected has text and a clip, and interrupts', () {
      final request = builder.nothingDetected();
      expect(request.text, isNotEmpty);
      expect(request.clipKeys, <String>['nothing_detected']);
      expect(request.interrupt, isTrue);
    });

    test('every clip key can be produced by the label tables', () {
      for (final int id in kurdishLabels.keys) {
        expect(clipKeyForClass(id), 'class_$id');
        expect(clipKeyForClassAlso(id), 'class_${id}_also');
      }
      for (final String key in <String>[
        'in_front',
        'on_left',
        'on_right',
        'exists',
        'and',
        'seen_one',
        'seen_many',
        'nothing_detected',
      ]) {
        expect(allClipTexts()[key], isNotEmpty, reason: key);
      }
      expect(
        allClipTexts().length,
        kurdishLabels.length * 2 + phraseFragments.length + 2,
      );
    });
  });
}
