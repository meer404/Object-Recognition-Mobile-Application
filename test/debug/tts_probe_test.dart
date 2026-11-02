import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:kurdish_vision/debug/probe_report.dart';
import 'package:kurdish_vision/debug/tts_probe.dart';

const MethodChannel _channel = MethodChannel('flutter_tts');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<String> calls = <String>[];

  late FlutterTts tts;
  late TtsProbe probe;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(_channel, (MethodCall call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'getEngines':
          throw PlatformException(code: 'UNSUPPORTED', message: 'iOS');
        case 'getLanguages':
          return <Object?>['en-US', 'ku-TR', 'ar-SA'];
        case 'getVoices':
          return <Object?>[
            <Object?, Object?>{'name': 'ku-tr-1', 'locale': 'ku-TR'},
          ];
        case 'isLanguageAvailable':
          return call.arguments == 'ku-TR';
        default:
          return 1;
      }
    });
    tts = FlutterTts();
    probe = TtsProbe(tts: tts, startTimeout: const Duration(milliseconds: 50));
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('inventory: Kurmanji is not mistaken for Sorani', () async {
    final TtsInventory inv = await probe.inventory();
    expect(inv.soraniSelectable, isFalse);
    expect(inv.soraniLanguages, isEmpty);
    expect(inv.otherKurdishLanguages, <String>['ku-TR']);
    expect(inv.otherKurdishVoices.single['name'], 'ku-tr-1');
    expect(inv.availability.keys, probeLanguageCodes);
    expect(inv.availability['ku-TR'], isTrue);
    expect(inv.availability['ckb'], isFalse);
  });

  test('a failing engine call is recorded, not fatal', () async {
    final TtsInventory inv = await probe.inventory();
    expect(inv.engines, isEmpty);
    expect(inv.errors['getEngines'], contains('UNSUPPORTED'));
  });

  test('trySpeak reports start latency when the engine starts', () async {
    final Future<SpeakAttempt> pending = probe.trySpeak('ckb');
    await Future<void>.delayed(Duration.zero);
    expect(calls, containsAllInOrder(<String>['setLanguage', 'speak']));
    await tts.platformCallHandler(const MethodCall('speak.onStart'));
    final SpeakAttempt a = await pending;
    expect(a.started, isTrue);
    expect(a.startLatencyMs, isNotNull);
    expect(a.label, 'TTS ckb');
  });

  test('trySpeak reports an engine error', () async {
    final Future<SpeakAttempt> pending = probe.trySpeak('ckb');
    await Future<void>.delayed(Duration.zero);
    await tts.platformCallHandler(
      const MethodCall('speak.onError', 'not supported'),
    );
    final SpeakAttempt a = await pending;
    expect(a.started, isFalse);
    expect(a.error, contains('not supported'));
  });

  test('trySpeak times out when nothing happens', () async {
    final SpeakAttempt a = await probe.trySpeak('ckb');
    expect(a.started, isFalse);
    expect(a.error, contains('no start'));
  });

  test('report states the verdicts and flags unrated attempts', () async {
    final TtsInventory inv = await probe.inventory();
    final SpeakAttempt rated = SpeakAttempt(
      label: 'TTS ku-TR',
      started: true,
      startLatencyMs: 120,
    )..verdict = HumanVerdict.notUnderstood;
    final SpeakAttempt unrated = SpeakAttempt(label: 'TTS ckb', started: false);

    final String md = buildProbeReport(
      deviceName: 'Pixel 7',
      inventory: inv,
      attempts: <SpeakAttempt>[rated, unrated],
      timestamp: DateTime.utc(2026, 11, 2),
    );
    expect(md, contains('### Speech probe: Pixel 7'));
    expect(md, contains('**App would use Sorani TTS:** NO'));
    expect(md, contains('`ku-TR`'));
    expect(md, contains('120.0'));
    expect(md, contains(HumanVerdict.notUnderstood.description));
    expect(md, contains('NOT RATED'));
    expect(md, contains('`getEngines`: UNSUPPORTED'));
  });
}
