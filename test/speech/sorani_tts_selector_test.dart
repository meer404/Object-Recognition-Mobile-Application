import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/speech/sorani_tts_selector.dart';

void main() {
  group('language codes', () {
    test('ckb in any spelling is Sorani', () {
      for (final String c in <String>['ckb', 'CKB', 'ckb-IQ', 'ckb_IR']) {
        expect(isSoraniCode(c), isTrue, reason: c);
      }
    });

    test('ku / kmr / sdh are Kurdish but NOT Sorani', () {
      for (final String c in <String>['ku', 'ku-TR', 'kmr', 'sdh-IR']) {
        expect(isSoraniCode(c), isFalse, reason: c);
        expect(isOtherKurdishCode(c), isTrue, reason: c);
      }
    });

    test('Arabic and Persian are neither', () {
      for (final String c in <String>['ar', 'ar-IQ', 'fa-IR']) {
        expect(isSoraniCode(c), isFalse);
        expect(isOtherKurdishCode(c), isFalse);
      }
    });
  });

  group('selectSoraniTts', () {
    test('typical device without Sorani → null', () {
      expect(
        selectSoraniTts(
          languages: <Object?>['en-US', 'ar', 'ku-TR', 'fa-IR'],
          voices: <Object?>[
            <Object?, Object?>{'name': 'ku-tr-x-a', 'locale': 'ku-TR'},
          ],
        ),
        isNull,
      );
    });

    test('prefers a Sorani voice over a bare language', () {
      final SoraniTtsChoice? c = selectSoraniTts(
        languages: <Object?>['ckb'],
        voices: <Object?>[
          <Object?, Object?>{'name': 'en-1', 'locale': 'en-US'},
          <Object?, Object?>{
            'name': 'ckb-voice',
            'locale': 'ckb-IQ',
            'quality': 300,
          },
        ],
      );
      expect(c?.language, 'ckb-IQ');
      expect(c?.voice?['name'], 'ckb-voice');
      expect(c?.voice?['quality'], '300');
    });

    test('falls back to the language when no voice matches', () {
      final SoraniTtsChoice? c = selectSoraniTts(
        languages: <Object?>['en', 'ckb_IQ'],
        voices: <Object?>[],
      );
      expect(c?.language, 'ckb_IQ');
      expect(c?.voice, isNull);
    });

    test('tolerates null and malformed engine output', () {
      expect(selectSoraniTts(languages: null, voices: null), isNull);
      expect(
        selectSoraniTts(
          languages: <Object?>[1, null],
          voices: <Object?>[
            'x',
            <Object?, Object?>{'name': 3},
          ],
        ),
        isNull,
      );
    });
  });
}
