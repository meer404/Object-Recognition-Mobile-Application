import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

void main() {
  group('AppSettings defaults match CLAUDE.md', () {
    const AppSettings s = AppSettings();

    test('inference rate is within 3–5 per second', () {
      expect(s.targetInferencesPerSecond, inInclusiveRange(3, 5));
    });

    test('confidence threshold is 0.5', () {
      expect(s.confidenceThreshold, 0.5);
    });

    test('confirmation is 2 of last 3', () {
      expect(s.confirmationHits, 2);
      expect(s.confirmationWindow, 3);
    });

    test('repeat cooldown is 5 s', () {
      expect(s.repeatCooldown, const Duration(seconds: 5));
    });

    test('at most 3 objects per sentence', () {
      expect(s.maxObjectsPerSentence, 3);
    });

    test('evaluation mode is off by default (privacy)', () {
      expect(s.evaluationMode, isFalse);
    });

    test('speech start timeout is set and copyWith keeps it', () {
      expect(s.speechStartTimeout, const Duration(seconds: 3));
      expect(
        s.copyWith(speechVolume: 0.5).speechStartTimeout,
        s.speechStartTimeout,
      );
    });
  });

  test('minInferenceInterval is derived from the rate', () {
    const AppSettings s = AppSettings(targetInferencesPerSecond: 4);
    expect(s.minInferenceInterval, const Duration(milliseconds: 250));
  });

  test('copyWith changes only the given fields', () {
    const AppSettings base = AppSettings();
    final AppSettings changed = base.copyWith(confidenceThreshold: 0.7);
    expect(changed.confidenceThreshold, 0.7);
    expect(changed.confirmationHits, base.confirmationHits);
    expect(changed.repeatCooldown, base.repeatCooldown);
  });

  test('rejects invalid configuration', () {
    expect(
      () => AppSettings(targetInferencesPerSecond: 30),
      throwsAssertionError,
    );
    expect(
      () => AppSettings(confirmationHits: 4, confirmationWindow: 3),
      throwsAssertionError,
    );
    expect(() => AppSettings(confidenceThreshold: 1.5), throwsAssertionError);
  });
}
