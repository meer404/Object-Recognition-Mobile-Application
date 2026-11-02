import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:kurdish_vision/speech/speech_service.dart';
import 'package:kurdish_vision/speech/tts_speech.dart';

const MethodChannel _channel = MethodChannel('flutter_tts');
const SpeechRequest _sentence = SpeechRequest(
  text: 'لەبەردەمت مێزێک هەیە',
  clipKeys: <String>[],
);

/// Fakes the native side of flutter_tts.
class _FakeEngine {
  _FakeEngine({required this.languages, this.voices = const <Object?>[]});

  final List<Object?> languages;
  final List<Object?> voices;
  final List<MethodCall> calls = <MethodCall>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getLanguages':
        return languages;
      case 'getVoices':
        return voices;
      default:
        return 1;
    }
  }

  List<String> get methods => <String>[
    for (final MethodCall c in calls) c.method,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late FlutterTts tts;

  Future<TtsSpeech> create(_FakeEngine engine) async {
    messenger.setMockMethodCallHandler(_channel, engine.handle);
    tts = FlutterTts();
    final TtsSpeech speech = TtsSpeech(
      tts: tts,
      startTimeout: const Duration(milliseconds: 50),
    );
    await speech.init();
    return speech;
  }

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('no Sorani on device: unsupported, never speaks', () async {
    final _FakeEngine engine = _FakeEngine(
      languages: <Object?>['en-US', 'ku-TR'],
    );
    final TtsSpeech speech = await create(engine);

    expect(await speech.supportsSorani, isFalse);
    expect(await speech.speak(_sentence), SpeechOutcome.failed);
    expect(engine.methods, isNot(contains('speak')));
    expect(engine.methods, isNot(contains('setLanguage')));
  });

  test('Sorani available: selects it and reports start', () async {
    final _FakeEngine engine = _FakeEngine(
      languages: <Object?>['en-US', 'ckb-IQ'],
    );
    final TtsSpeech speech = await create(engine);
    expect(await speech.supportsSorani, isTrue);
    expect(
      engine.calls
          .firstWhere((MethodCall c) => c.method == 'setLanguage')
          .arguments,
      'ckb-IQ',
    );

    final Future<SpeechOutcome> outcome = speech.speak(_sentence);
    await Future<void>.delayed(Duration.zero);
    expect(engine.methods, contains('speak'));
    await tts.platformCallHandler(const MethodCall('speak.onStart'));
    expect(await outcome, SpeechOutcome.started);

    await tts.platformCallHandler(const MethodCall('speak.onComplete'));
    await Future<void>.delayed(Duration.zero);
    expect(speech.speaking, isFalse);
  });

  test('a Sorani voice is applied with setVoice', () async {
    final _FakeEngine engine = _FakeEngine(
      languages: <Object?>['ckb'],
      voices: <Object?>[
        <Object?, Object?>{'name': 'ckb-x-1', 'locale': 'ckb-IQ'},
      ],
    );
    final TtsSpeech speech = await create(engine);
    expect(speech.choice?.voice?['name'], 'ckb-x-1');
    final Object? voiceArgs = engine.calls
        .firstWhere((MethodCall c) => c.method == 'setVoice')
        .arguments;
    expect(voiceArgs, <String, String>{'name': 'ckb-x-1', 'locale': 'ckb-IQ'});
  });

  test('engine that never starts fails after the timeout', () async {
    final TtsSpeech speech = await create(
      _FakeEngine(languages: <Object?>['ckb']),
    );
    expect(await speech.speak(_sentence), SpeechOutcome.failed);
    expect(speech.speaking, isFalse);
  });

  test('empty text is not sent to the engine', () async {
    final _FakeEngine engine = _FakeEngine(languages: <Object?>['ckb']);
    final TtsSpeech speech = await create(engine);
    expect(
      await speech.speak(const SpeechRequest(text: '  ', clipKeys: <String>[])),
      SpeechOutcome.nothingToSay,
    );
    expect(engine.methods, isNot(contains('speak')));
  });
}
