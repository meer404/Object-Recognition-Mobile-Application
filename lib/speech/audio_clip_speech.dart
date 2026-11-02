import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import 'clip_manifest.dart';
import 'clip_player.dart';
import 'just_audio_clip_player.dart';
import 'speech_serializer.dart';
import 'speech_service.dart';

/// PRIMARY speech path: plays pre-recorded Sorani clips from assets/audio/,
/// concatenated in [SpeechRequest.clipKeys] order.
///
/// Missing clips are skipped and recorded in [missingClipKeys], so a gap in
/// the recordings degrades the sentence instead of crashing the app.
class AudioClipSpeech implements SpeechService {
  AudioClipSpeech({
    required ClipPlayer player,
    required Future<ClipManifest> Function() loadManifest,
  }) : _player = player,
       _loadManifest = loadManifest {
    _serializer = SpeechSerializer<List<String>>(
      perform: (List<String> paths, void Function() onStarted) =>
          _player.playSequence(paths, onStarted: onStarted),
      stopCurrent: _player.stop,
    );
  }

  /// Production wiring: just_audio + the bundled manifest.
  factory AudioClipSpeech.standard() => AudioClipSpeech(
    player: JustAudioClipPlayer(),
    loadManifest: () => ClipManifest.load(rootBundle),
  );

  final ClipPlayer _player;
  final Future<ClipManifest> Function() _loadManifest;
  late final SpeechSerializer<List<String>> _serializer;
  final Set<String> _missingClipKeys = <String>{};
  ClipManifest? _manifest;

  /// Clip keys that were requested but are not in the manifest.
  Set<String> get missingClipKeys => Set<String>.unmodifiable(_missingClipKeys);

  @override
  Future<void> init() async {
    _manifest = await _loadManifest();
    await _player.init();
  }

  /// Recorded clips are Sorani by construction once the manifest is loaded.
  @override
  Future<bool> get supportsSorani async => _manifest != null;

  @override
  Future<SpeechOutcome> speak(SpeechRequest request) {
    final ClipManifest? manifest = _manifest;
    if (manifest == null) {
      throw StateError('AudioClipSpeech.init() must complete before speak()');
    }
    final List<String> missing = <String>[];
    final List<String> paths = manifest.resolve(
      request.clipKeys,
      missing: missing,
    );
    if (missing.isNotEmpty) {
      _missingClipKeys.addAll(missing);
      developer.log('missing clips skipped: $missing', name: 'speech');
    }
    if (paths.isEmpty) {
      return Future<SpeechOutcome>.value(SpeechOutcome.nothingToSay);
    }
    return _serializer.submit(paths, interrupt: request.interrupt);
  }

  @override
  Future<void> stop() => _serializer.stop();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  bool get speaking => _serializer.speaking;

  @override
  Stream<bool> get isSpeaking => _serializer.isSpeaking;

  @override
  Future<void> dispose() async {
    await _serializer.dispose();
    await _player.dispose();
  }
}
