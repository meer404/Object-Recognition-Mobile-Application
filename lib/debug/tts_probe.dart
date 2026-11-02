import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../speech/sorani_tts_selector.dart';

/// The Sorani test sentence from CLAUDE.md ("There is a table in front of
/// you.").
const String probeTestSentence = 'لەبەردەمت مێزێک هەیە';

/// Codes passed to `isLanguageAvailable`. Every one is probed and reported,
/// whatever the result; nothing is assumed.
const List<String> probeLanguageCodes = <String>[
  'ckb',
  'ckb-IQ',
  'ckb-IR',
  'ku',
  'ku-IQ',
  'ku-TR',
];

/// What a human heard when an attempt was played.
enum HumanVerdict {
  understood('Understood: correct Sorani'),
  partly('Partly understandable'),
  notUnderstood('Not understandable / wrong language'),
  silent('Nothing was heard');

  const HumanVerdict(this.description);
  final String description;
}

/// Everything the TTS engine reports about itself.
class TtsInventory {
  const TtsInventory({
    required this.platform,
    required this.engines,
    required this.defaultEngine,
    required this.languages,
    required this.voices,
    required this.availability,
    required this.errors,
  });

  final String platform;
  final List<String> engines;
  final String? defaultEngine;
  final List<String> languages;
  final List<Map<String, String>> voices;

  /// `isLanguageAvailable` per code in [probeLanguageCodes]. Null = call failed.
  final Map<String, bool?> availability;

  /// Calls that threw (e.g. Android-only methods on iOS).
  final Map<String, String> errors;

  List<String> get soraniLanguages => languages.where(isSoraniCode).toList();

  List<String> get otherKurdishLanguages =>
      languages.where(isOtherKurdishCode).toList();

  List<Map<String, String>> get soraniVoices => voices
      .where((Map<String, String> v) => isSoraniCode(v['locale']!))
      .toList();

  List<Map<String, String>> get otherKurdishVoices => voices
      .where((Map<String, String> v) => isOtherKurdishCode(v['locale']!))
      .toList();

  /// Same rule as TtsSpeech: does the app consider Sorani TTS available?
  bool get soraniSelectable =>
      soraniLanguages.isNotEmpty || soraniVoices.isNotEmpty;
}

/// One attempt to speak [probeTestSentence].
class SpeakAttempt {
  SpeakAttempt({
    required this.label,
    required this.started,
    this.startLatencyMs,
    this.setLanguageResult,
    this.error,
  });

  /// e.g. `TTS ckb-IQ` or `Recorded clip`.
  final String label;
  final bool started;
  final double? startLatencyMs;
  final Object? setLanguageResult;
  final String? error;

  /// Filled in by the human listener on the probe screen.
  HumanVerdict? verdict;
}

/// Collects TTS facts from the device and runs speak attempts.
class TtsProbe {
  TtsProbe({required this.startTimeout, FlutterTts? tts})
    : _tts = tts ?? FlutterTts();

  final Duration startTimeout;
  final FlutterTts _tts;

  Future<TtsInventory> inventory() async {
    final Map<String, String> errors = <String, String>{};

    Future<Object?> guarded(
      String name,
      Future<Object?> Function() call,
    ) async {
      try {
        return await call();
      } on Object catch (e) {
        errors[name] = e is PlatformException
            ? '${e.code}: ${e.message}'
            : '$e';
        return null;
      }
    }

    final Object? engines = await guarded('getEngines', () => _tts.getEngines);
    final Object? defaultEngine = await guarded(
      'getDefaultEngine',
      () => _tts.getDefaultEngine,
    );
    final Object? languages = await guarded(
      'getLanguages',
      () => _tts.getLanguages,
    );
    final Object? voices = await guarded('getVoices', () => _tts.getVoices);

    final Map<String, bool?> availability = <String, bool?>{};
    for (final String code in probeLanguageCodes) {
      final Object? result = await guarded(
        'isLanguageAvailable($code)',
        () => _tts.isLanguageAvailable(code),
      );
      availability[code] = result is bool ? result : null;
    }

    final List<String> languageList = parseLanguages(languages)..sort();
    return TtsInventory(
      platform:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      engines: <String>[
        if (engines is List<Object?>)
          for (final Object? e in engines) '$e',
      ],
      defaultEngine: defaultEngine?.toString(),
      languages: languageList,
      voices: parseVoices(voices),
      availability: availability,
      errors: errors,
    );
  }

  /// Sets [language] and speaks the test sentence. Returns once speech
  /// started, failed, or [startTimeout] passed. The sentence keeps playing so
  /// the listener can judge it.
  Future<SpeakAttempt> trySpeak(String language) async {
    final Completer<String?> outcome = Completer<String?>();
    final Stopwatch stopwatch = Stopwatch();
    _tts
      ..setStartHandler(() {
        if (!outcome.isCompleted) outcome.complete(null);
      })
      ..setErrorHandler((dynamic message) {
        if (!outcome.isCompleted) outcome.complete('engine error: $message');
      });

    Object? setResult;
    try {
      await _tts.stop();
      setResult = await _tts.setLanguage(language);
      stopwatch.start();
      await _tts.speak(probeTestSentence, focus: true);
    } on Object catch (e) {
      return SpeakAttempt(
        label: 'TTS $language',
        started: false,
        setLanguageResult: setResult,
        error: '$e',
      );
    }

    final String? error = await outcome.future.timeout(
      startTimeout,
      onTimeout: () => 'no start within ${startTimeout.inMilliseconds} ms',
    );
    stopwatch.stop();
    return SpeakAttempt(
      label: 'TTS $language',
      started: error == null,
      startLatencyMs: error == null
          ? stopwatch.elapsedMicroseconds / 1000
          : null,
      setLanguageResult: setResult,
      error: error,
    );
  }

  Future<void> stop() async => _tts.stop();
}
