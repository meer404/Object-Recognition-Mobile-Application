/// Decides whether a TTS engine's languages/voices include Sorani.
///
/// Language-code facts this relies on (ISO 639-3 / BCP 47):
/// - `ckb` = Central Kurdish (Sorani, Arabic script). This is what we need.
/// - `ku` = Kurdish macrolanguage. In practice TTS engines use it for
///   KURMANJI (Latin script, e.g. `ku-TR`), NOT Sorani. It is never treated
///   as Sorani; the probe screen lists it separately so a human can listen.
/// - `kmr` = Kurmanji, `sdh` = Southern Kurdish. Not Sorani.
library;

/// The language (and optionally voice) to use for Sorani TTS.
class SoraniTtsChoice {
  const SoraniTtsChoice({required this.language, this.voice});

  /// Language code exactly as reported by the engine (e.g. `ckb-IQ`).
  final String language;

  /// Voice map as reported by flutter_tts (`name`, `locale`), if one matched.
  final Map<String, String>? voice;
}

/// Lower-cases and splits a locale such as `ckb_IQ` or `ckb-IQ`.
String primaryLanguageSubtag(String code) =>
    code.trim().toLowerCase().split(RegExp('[-_]')).first;

/// True only for Central Kurdish (Sorani).
bool isSoraniCode(String code) => primaryLanguageSubtag(code) == 'ckb';

/// True for Kurdish codes that are NOT Sorani (`ku`, `kmr`, `sdh`).
bool isOtherKurdishCode(String code) =>
    const <String>{'ku', 'kmr', 'sdh'}.contains(primaryLanguageSubtag(code));

/// Picks a Sorani language and voice, or returns null if there is none.
///
/// [languages] and [voices] are the raw, untyped results of flutter_tts
/// `getLanguages` / `getVoices`. Entries of unexpected shape are ignored.
SoraniTtsChoice? selectSoraniTts({
  required Object? languages,
  required Object? voices,
}) {
  final List<Map<String, String>> soraniVoices = <Map<String, String>>[
    for (final Map<String, String> v in parseVoices(voices))
      if (isSoraniCode(v['locale'] ?? '')) v,
  ];
  if (soraniVoices.isNotEmpty) {
    final Map<String, String> voice = soraniVoices.first;
    return SoraniTtsChoice(language: voice['locale']!, voice: voice);
  }
  for (final String language in parseLanguages(languages)) {
    if (isSoraniCode(language)) return SoraniTtsChoice(language: language);
  }
  return null;
}

/// Converts flutter_tts `getLanguages` output to a list of strings.
List<String> parseLanguages(Object? raw) => <String>[
  if (raw is List<Object?>)
    for (final Object? item in raw)
      if (item is String) item,
];

/// Converts flutter_tts `getVoices` output to string maps with a `name`
/// and a `locale`. Other keys (quality, gender, ...) are kept as strings.
List<Map<String, String>> parseVoices(Object? raw) => <Map<String, String>>[
  if (raw is List<Object?>)
    for (final Object? item in raw)
      if (item is Map<Object?, Object?> &&
          item['name'] is String &&
          item['locale'] is String)
        <String, String>{
          for (final MapEntry<Object?, Object?> e in item.entries)
            if (e.key is String && e.value != null)
              e.key! as String: e.value.toString(),
        },
];
