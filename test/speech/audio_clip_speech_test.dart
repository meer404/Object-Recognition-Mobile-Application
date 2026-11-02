import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/speech/audio_clip_speech.dart';
import 'package:kurdish_vision/speech/clip_manifest.dart';
import 'package:kurdish_vision/speech/clip_player.dart';
import 'package:kurdish_vision/speech/speech_service.dart';

class _FakeClipPlayer implements ClipPlayer {
  final List<List<String>> played = <List<String>>[];
  final List<double> volumes = <double>[];
  bool initialized = false;
  bool disposed = false;
  Completer<void>? _done;

  @override
  Future<void> init() async => initialized = true;

  @override
  Future<void> playSequence(
    List<String> assetPaths, {
    required void Function() onStarted,
  }) {
    played.add(assetPaths);
    _done = Completer<void>();
    onStarted();
    return _done!.future;
  }

  void finish() => _done?.complete();

  @override
  Future<void> stop() async {
    if (_done != null && !_done!.isCompleted) _done!.complete();
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> dispose() async => disposed = true;
}

SpeechRequest _req(List<String> keys) =>
    SpeechRequest(text: 'test', clipKeys: keys);

void main() {
  late _FakeClipPlayer player;
  late AudioClipSpeech speech;

  setUp(() async {
    player = _FakeClipPlayer();
    speech = AudioClipSpeech(
      player: player,
      loadManifest: () async => ClipManifest(<String, String>{
        'in_front': 'in_front.m4a',
        'class_56': 'class_56.m4a',
      }),
    );
    await speech.init();
  });

  tearDown(() => speech.dispose());

  test('init prepares the player and reports Sorani support', () async {
    expect(player.initialized, isTrue);
    expect(await speech.supportsSorani, isTrue);
  });

  test('speak before init throws', () {
    final AudioClipSpeech fresh = AudioClipSpeech(
      player: _FakeClipPlayer(),
      loadManifest: () async => ClipManifest(<String, String>{}),
    );
    expect(() => fresh.speak(_req(<String>['x'])), throwsStateError);
  });

  test('plays clips in request order as one sequence', () async {
    final SpeechOutcome outcome = await speech.speak(
      _req(<String>['in_front', 'class_56']),
    );
    expect(outcome, SpeechOutcome.started);
    expect(player.played.single, <String>[
      'assets/audio/in_front.m4a',
      'assets/audio/class_56.m4a',
    ]);
  });

  test('missing clips are skipped and remembered', () async {
    await speech.speak(_req(<String>['in_front', 'class_99']));
    expect(player.played.single, <String>['assets/audio/in_front.m4a']);
    expect(speech.missingClipKeys, <String>{'class_99'});
  });

  test('nothing playable → nothingToSay, player untouched', () async {
    expect(
      await speech.speak(_req(<String>['nope'])),
      SpeechOutcome.nothingToSay,
    );
    expect(player.played, isEmpty);
  });

  test('second request waits for the first (no overlap)', () async {
    await speech.speak(_req(<String>['in_front']));
    final Future<SpeechOutcome> second = speech.speak(
      _req(<String>['class_56']),
    );
    await Future<void>.delayed(Duration.zero);
    expect(player.played.length, 1);

    player.finish();
    expect(await second, SpeechOutcome.started);
    expect(player.played.length, 2);
  });

  test('volume is forwarded and dispose releases the player', () async {
    await speech.setVolume(0.4);
    expect(player.volumes, <double>[0.4]);
    await speech.dispose();
    expect(player.disposed, isTrue);
  });
}
