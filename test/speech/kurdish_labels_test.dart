import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/ui_strings.dart';
import 'package:kurdish_vision/speech/kurdish_labels.dart';

void main() {
  final List<String> modelLabels = File(
    'assets/models/labels.txt',
  ).readAsLinesSync().where((String l) => l.trim().isNotEmpty).toList();

  test('the model label file has the 80 COCO classes', () {
    expect(modelLabels, hasLength(80));
  });

  test('class count is within the 15–20 scope', () {
    expect(kurdishLabels.length, inInclusiveRange(15, 20));
  });

  test('every id points at the intended model class', () {
    kurdishLabels.forEach((int id, KurdishLabel label) {
      expect(id, inInclusiveRange(0, modelLabels.length - 1));
      expect(modelLabels[id], label.modelName, reason: 'class id $id');
    });
  });

  test('every label has both Sorani forms, in Arabic script', () {
    final RegExp arabicScript = RegExp(r'^[؀-ۿ ]+$');
    kurdishLabels.forEach((int id, KurdishLabel label) {
      expect(label.word, matches(arabicScript), reason: 'word of $id');
      expect(
        label.indefinite,
        matches(arabicScript),
        reason: 'indefinite of $id',
      );
      expect(label.indefinite, isNot(label.word), reason: 'forms of $id');
      expect(
        label.indefiniteAlso,
        matches(arabicScript),
        reason: 'also form of $id',
      );
      expect(label.indefiniteAlso, endsWith('یش'), reason: 'also form of $id');
    });
  });

  test('no two classes share a spoken word', () {
    final List<String> words = <String>[
      for (final KurdishLabel label in kurdishLabels.values) label.word,
    ];
    expect(words.toSet(), hasLength(words.length));
  });

  test('every entry still unverified carries a REVIEW comment', () {
    final String source = File(
      'lib/speech/kurdish_labels.dart',
    ).readAsStringSync();
    final int reviewed = RegExp(
      r'^\s*// REVIEW',
      multiLine: true,
    ).allMatches(source).length;
    expect(reviewed, kurdishLabels.length + 1, reason: 'labels + fragments');
  });

  test('the review sheet lists every sentence piece', () {
    final String sheet = File('docs/kurdish_labels.md').readAsStringSync();
    phraseFragments.forEach((String key, String text) {
      expect(sheet, contains('| $key | $text |'));
    });
  });

  test('the review sheet lists every UI string', () {
    final String sheet = File('docs/kurdish_labels.md').readAsStringSync();
    for (final String text in UiStrings.all) {
      expect(sheet, contains('| $text |'));
    }
  });

  test('the review sheet mirrors the code', () {
    final String sheet = File('docs/kurdish_labels.md').readAsStringSync();
    kurdishLabels.forEach((int id, KurdishLabel label) {
      expect(
        sheet,
        contains(
          '| $id | ${label.modelName} | ${label.word} | '
          '${label.indefinite} | ${label.indefiniteAlso} |',
        ),
        reason: 'class id $id',
      );
    });
  });
}
