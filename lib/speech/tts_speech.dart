import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'sorani_tts_selector.dart';
import 'speech_serializer.dart';
import 'speech_service.dart';

/// OPTIONAL speech path via system TTS (`flutter_tts`).
///
/// It is used only if the engine reports a Sorani (`ckb`) language or voice.
/// Most devices are expected NOT to have one. Without one, [speak] returns
/// [SpeechOutcome.failed] and never reads Sorani text with a non-Sorani
/// voice. Even with one, whether it is *intelligible* needs a human check
/// (speech probe screen).
class TtsSpeech implements SpeechService {
  TtsSpeech({required Duration startTimeout, FlutterTts? tts})
    : _startTimeout = startTimeout,
      _tts = tts ?? FlutterTts() {
    _serializer = SpeechSerializer<String>(
      perform: _speakOnce,
      stopCurrent: () async {
        await _tts.stop();
        _endUtterance();
      },
    );
  }

  final Duration _startTimeout;
  final FlutterTts _tts;
  late final SpeechSerializer<String> _serializer;

  SoraniTtsChoice? _choice;
  Completer<void>? _utterance;
  void Function()? _onStarted;

  /// The selected Sorani language/voice, or null if the device has none.
  SoraniTtsChoice? get choice => _choice;

  @override
  Future<void> init() async {
    _tts
      ..setStartHandler(() => _onStarted?.call())
      ..setCompletionHandler(_endUtterance)
      ..setCancelHandler(_endUtterance)
      ..setErrorHandler((dynamic message) {
        developer.log('TTS error: $message', name: 'speech');
        _endUtterance();
      });
    await _tts.awaitSpeakCompletion(false);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        <IosTextToSpeechAudioCategoryOptions>[
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.spokenAudio,
      );
    }

    _choice = selectSoraniTts(
      languages: await _tts.getLanguages,
      voices: await _tts.getVoices,
    );
    final SoraniTtsChoice? choice = _choice;
    if (choice != null) {
      await _tts.setLanguage(choice.language);
      final Map<String, String>? voice = choice.voice;
      if (voice != null) await _tts.setVoice(voice);
    }
  }

  @override
  Future<bool> get supportsSorani async => _choice != null;

  @override
  Future<SpeechOutcome> speak(SpeechRequest request) {
    if (_choice == null) {
      return Future<SpeechOutcome>.value(SpeechOutcome.failed);
    }
    if (request.text.trim().isEmpty) {
      return Future<SpeechOutcome>.value(SpeechOutcome.nothingToSay);
    }
    return _serializer.submit(request.text, interrupt: request.interrupt);
  }

  Future<void> _speakOnce(String text, void Function() onStarted) async {
    final Completer<void> utterance = Completer<void>();
    bool started = false;
    _utterance = utterance;
    _onStarted = () {
      started = true;
      onStarted();
    };
    // Android: focus=true requests AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK.
    await _tts.speak(text, focus: true);
    // A silent engine must not block speech forever.
    final Timer watchdog = Timer(_startTimeout, () {
      if (!started) {
        developer.log('TTS did not start in $_startTimeout', name: 'speech');
        unawaited(_tts.stop());
        _endUtterance();
      }
    });
    try {
      await utterance.future;
    } finally {
      watchdog.cancel();
      _onStarted = null;
    }
  }

  void _endUtterance() {
    final Completer<void>? utterance = _utterance;
    _utterance = null;
    if (utterance != null && !utterance.isCompleted) utterance.complete();
  }

  @override
  Future<void> stop() => _serializer.stop();

  @override
  Future<void> setVolume(double volume) async => _tts.setVolume(volume);

  @override
  bool get speaking => _serializer.speaking;

  @override
  Stream<bool> get isSpeaking => _serializer.isSpeaking;

  @override
  Future<void> dispose() async {
    await _serializer.dispose();
    await _tts.stop();
  }
}
