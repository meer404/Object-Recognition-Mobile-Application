import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'clip_player.dart';

/// [ClipPlayer] backed by `just_audio` with an `audio_session` setup that
/// DUCKS other audio instead of pausing or masking it (CLAUDE.md).
///
/// Ducking only ends when the session is deactivated, and `just_audio` never
/// deactivates it. So we deactivate after every utterance, with
/// notifyOthersOnDeactivation so other apps restore their volume.
class JustAudioClipPlayer implements ClipPlayer {
  JustAudioClipPlayer() : _player = AudioPlayer();

  /// Speech that briefly lowers other audio (D-007).
  ///
  /// Android usage is `media` so the hardware volume keys control it.
  /// `assistanceAccessibility` would tie it to the accessibility volume.
  static const AudioSessionConfiguration sessionConfiguration =
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      );

  final AudioPlayer _player;
  AudioSession? _session;
  int _generation = 0;

  @override
  Future<void> init() async {
    final AudioSession session = await AudioSession.instance;
    await session.configure(sessionConfiguration);
    _session = session;
  }

  @override
  Future<void> playSequence(
    List<String> assetPaths, {
    required void Function() onStarted,
  }) async {
    final int generation = ++_generation;
    await _player.setAudioSources(<AudioSource>[
      for (final String path in assetPaths) AudioSource.asset(path),
    ]);
    // stop() was called while loading: do not start playing.
    if (generation != _generation) return;

    bool started = false;
    final StreamSubscription<PlayerState> subscription = _player
        .playerStateStream
        .listen((PlayerState state) {
          if (!started &&
              state.playing &&
              state.processingState == ProcessingState.ready) {
            started = true;
            onStarted();
          }
        });
    try {
      // Completes when playback completes or is stopped.
      await _player.play();
    } finally {
      await subscription.cancel();
      await _player.stop();
      await _session?.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    }
  }

  @override
  Future<void> stop() {
    _generation++;
    return _player.stop();
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
