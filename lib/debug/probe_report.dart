import 'tts_probe.dart';

/// Renders probe results as Markdown, ready to paste into
/// docs/decisions.md (D-009, one block per device).
String buildProbeReport({
  required String deviceName,
  required TtsInventory inventory,
  required List<SpeakAttempt> attempts,
  required DateTime timestamp,
}) {
  final StringBuffer b = StringBuffer()
    ..writeln(
      '### Speech probe: ${deviceName.trim().isEmpty ? '(device not named)' : deviceName.trim()}',
    )
    ..writeln('- **Date:** ${timestamp.toIso8601String()}')
    ..writeln('- **OS:** ${inventory.platform}')
    ..writeln(
      '- **App would use Sorani TTS:** '
      '${inventory.soraniSelectable ? 'YES' : 'NO'}',
    )
    ..writeln('- **Default engine:** ${inventory.defaultEngine ?? 'n/a'}')
    ..writeln('- **Engines:** ${_list(inventory.engines)}')
    ..writeln('- **Languages reported:** ${inventory.languages.length}')
    ..writeln(
      '- **Sorani (ckb) languages:** ${_list(inventory.soraniLanguages)}',
    )
    ..writeln(
      '- **Other Kurdish (ku/kmr/sdh) languages:** '
      '${_list(inventory.otherKurdishLanguages)}',
    )
    ..writeln('- **Voices reported:** ${inventory.voices.length}')
    ..writeln('- **Sorani voices:** ${_voices(inventory.soraniVoices)}')
    ..writeln(
      '- **Other Kurdish voices:** ${_voices(inventory.otherKurdishVoices)}',
    )
    ..writeln('- **isLanguageAvailable:**');
  inventory.availability.forEach((String code, bool? ok) {
    b.writeln('  - `$code`: ${ok ?? 'call failed'}');
  });
  if (inventory.errors.isNotEmpty) {
    b.writeln('- **Calls that failed:**');
    inventory.errors.forEach((String call, String error) {
      b.writeln('  - `$call`: $error');
    });
  }
  b
    ..writeln()
    ..writeln('Test sentence: «$probeTestSentence»')
    ..writeln()
    ..writeln(
      '| Attempt | Started | Start latency (ms) | setLanguage | Error | Human verdict |',
    )
    ..writeln('|---|---|---|---|---|---|');
  if (attempts.isEmpty) {
    b.writeln('| (none) | | | | | |');
  }
  for (final SpeakAttempt a in attempts) {
    b.writeln(
      '| ${a.label} | ${a.started ? 'yes' : 'no'} | '
      '${a.startLatencyMs?.toStringAsFixed(1) ?? '–'} | '
      '${a.setLanguageResult ?? '–'} | ${a.error ?? ''} | '
      '${a.verdict?.description ?? 'NOT RATED'} |',
    );
  }
  b
    ..writeln()
    ..writeln(
      '_Language/voice lists come from the engine. Intelligibility comes only '
      'from the human verdict column._',
    );
  return b.toString();
}

String _list(List<String> items) =>
    items.isEmpty ? 'none' : items.map((String s) => '`$s`').join(', ');

String _voices(List<Map<String, String>> voices) => voices.isEmpty
    ? 'none'
    : voices
          .map((Map<String, String> v) => '`${v['name']}` (${v['locale']})')
          .join(', ');
