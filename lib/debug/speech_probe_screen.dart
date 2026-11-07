import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings/app_settings.dart';
import '../speech/audio_clip_speech.dart';
import '../speech/clip_manifest.dart';
import '../speech/just_audio_clip_player.dart';
import '../speech/speech_service.dart';
import 'probe_report.dart';
import 'tts_probe.dart';

/// Clip key played by the "recorded clip" test.
const String probeClipKey = 'test_sentence';

/// Synthetic Sorani test clip, for evaluation only. The file is git-ignored
/// and may be absent, in which case the attempt reports a failure. It is
/// not in the committed manifest because the free kurdishtts.com plan forbids
/// publishing its audio (decisions.md D-015).
const String probeLocalClipKey = 'test_sentence_tts';
const String probeLocalClipFile = 'local/test_sentence_tts.mp3';

/// DEBUG-ONLY researcher tool (Phase 1A). It lists TTS engines, languages and
/// voices, tries to speak the Sorani test sentence, plays a recorded clip,
/// collects a human verdict for each, and copies a Markdown report.
///
/// English labels on purpose: this screen is for the researcher, not for
/// end users (decisions.md D-010).
class SpeechProbeScreen extends StatefulWidget {
  const SpeechProbeScreen({super.key, this.settings = const AppSettings()});

  final AppSettings settings;

  @override
  State<SpeechProbeScreen> createState() => _SpeechProbeScreenState();
}

class _SpeechProbeScreenState extends State<SpeechProbeScreen> {
  late final TtsProbe _probe = TtsProbe(
    startTimeout: widget.settings.speechStartTimeout,
  );
  final AudioClipSpeech _clips = AudioClipSpeech(
    player: JustAudioClipPlayer(),
    loadManifest: () async => (await ClipManifest.load(
      rootBundle,
    )).withClips(<String, String>{probeLocalClipKey: probeLocalClipFile}),
  );
  final TextEditingController _device = TextEditingController();
  final List<SpeakAttempt> _attempts = <SpeakAttempt>[];

  TtsInventory? _inventory;
  String? _loadError;
  bool _clipsReady = false;
  String? _clipError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // Clip setup failing must not hide the TTS results, and vice versa.
    try {
      await _clips.init();
      _clipsReady = true;
    } on Object catch (e) {
      _clipError = '$e';
    }
    try {
      final TtsInventory inventory = await _probe.inventory();
      if (mounted) setState(() => _inventory = inventory);
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  @override
  void dispose() {
    unawaited(_probe.stop());
    unawaited(_clips.dispose());
    _device.dispose();
    super.dispose();
  }

  Future<void> _run(Future<SpeakAttempt> Function() attempt) async {
    setState(() => _busy = true);
    final SpeakAttempt result = await attempt();
    if (!mounted) return;
    setState(() {
      _attempts.add(result);
      _busy = false;
    });
  }

  Future<SpeakAttempt> _playClip(String key, String label) async {
    if (!_clipsReady) {
      return SpeakAttempt(
        label: label,
        started: false,
        error: 'clip player not ready: $_clipError',
      );
    }
    await _probe.stop();
    final Stopwatch watch = Stopwatch()..start();
    final SpeechOutcome outcome = await _clips.speak(
      SpeechRequest(
        text: probeTestSentence,
        clipKeys: <String>[key],
        interrupt: true,
      ),
    );
    watch.stop();
    final bool started = outcome == SpeechOutcome.started;
    return SpeakAttempt(
      label: label,
      started: started,
      startLatencyMs: started ? watch.elapsedMicroseconds / 1000 : null,
      error: started ? null : 'outcome: ${outcome.name}',
    );
  }

  Future<void> _copyReport() async {
    final TtsInventory? inventory = _inventory;
    if (inventory == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: buildProbeReport(
          deviceName: _device.text,
          inventory: inventory,
          attempts: _attempts,
          timestamp: DateTime.now(),
        ),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Report copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final TtsInventory? inventory = _inventory;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: const Text('Speech probe (debug)')),
        body: _loadError != null
            ? Center(child: Text('Probe failed: $_loadError'))
            : inventory == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(context, inventory),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TtsInventory inventory) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> tryLanguages = <String>{
      ...inventory.soraniLanguages,
      ...inventory.otherKurdishLanguages,
      ...probeLanguageCodes,
      if (inventory.languages.any(
        (String l) => l.toLowerCase().startsWith('ar'),
      ))
        'ar',
    }.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _device,
          decoration: const InputDecoration(
            labelText: 'Device model (for the report)',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          inventory.soraniSelectable
              ? 'Sorani TTS reported by engine: YES'
              : 'Sorani TTS reported by engine: NO',
          style: text.titleLarge,
        ),
        Text('OS: ${inventory.platform}'),
        Text('Default engine: ${inventory.defaultEngine ?? 'n/a'}'),
        Text(
          '${inventory.languages.length} languages, '
          '${inventory.voices.length} voices',
        ),
        Text('Sorani languages: ${_join(inventory.soraniLanguages)}'),
        Text('Other Kurdish: ${_join(inventory.otherKurdishLanguages)}'),
        for (final MapEntry<String, bool?> e in inventory.availability.entries)
          Text('isLanguageAvailable(${e.key}): ${e.value ?? 'call failed'}'),
        ExpansionTile(
          title: Text('All languages (${inventory.languages.length})'),
          children: <Widget>[SelectableText(inventory.languages.join(', '))],
        ),
        const Divider(height: 32),
        Text('Try the sentence «$probeTestSentence»', style: text.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String lang in tryLanguages)
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _run(() => _probe.trySpeak(lang)),
                child: Text('TTS $lang'),
              ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _playClip(probeClipKey, 'Placeholder tone clip'),
                    ),
              child: const Text('Placeholder tone clip'),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _playClip(
                        probeLocalClipKey,
                        'Synthetic Sorani clip (kurdishtts sorani_85 v3)',
                      ),
                    ),
              child: const Text('Synthetic Sorani clip (local)'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('Attempts: rate what you HEARD', style: text.titleMedium),
        for (final SpeakAttempt a in _attempts)
          _AttemptCard(
            attempt: a,
            onVerdict: (HumanVerdict v) => setState(() => a.verdict = v),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _copyReport,
          icon: const Icon(Icons.copy),
          label: const Text('Copy Markdown report'),
        ),
      ],
    );
  }

  static String _join(List<String> items) =>
      items.isEmpty ? 'none' : items.join(', ');
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({required this.attempt, required this.onVerdict});

  final SpeakAttempt attempt;
  final ValueChanged<HumanVerdict> onVerdict;

  @override
  Widget build(BuildContext context) {
    final String status = attempt.started
        ? 'started after ${attempt.startLatencyMs?.toStringAsFixed(0)} ms'
        : 'did not start: ${attempt.error}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${attempt.label}: $status'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final HumanVerdict v in HumanVerdict.values)
                  ChoiceChip(
                    label: Text(v.description),
                    selected: attempt.verdict == v,
                    onSelected: (_) => onVerdict(v),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
