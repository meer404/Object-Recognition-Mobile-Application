import 'dart:convert';

import 'package:flutter/services.dart';

/// Maps clip keys (e.g. `class_56`, `in_front_of_you`) to audio files under
/// assets/audio/. The file format is documented in docs/audio_recording.md.
///
/// ```json
/// { "version": 1, "clips": { "test_sentence": "placeholder/test_sentence.wav" } }
/// ```
class ClipManifest {
  ClipManifest(Map<String, String> clips)
    : _clips = Map<String, String>.unmodifiable(clips);

  /// Parses manifest JSON. Throws [FormatException] if it is malformed.
  factory ClipManifest.fromJson(String source) {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('manifest root must be an object');
    }
    if (decoded['version'] != supportedVersion) {
      throw FormatException(
        'unsupported manifest version: ${decoded['version']}',
      );
    }
    final Object? clips = decoded['clips'];
    if (clips is! Map<String, Object?>) {
      throw const FormatException('"clips" must be an object');
    }
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, Object?> entry in clips.entries) {
      final Object? file = entry.value;
      if (file is! String || file.isEmpty) {
        throw FormatException('clip "${entry.key}" must map to a file name');
      }
      result[entry.key] = file;
    }
    return ClipManifest(result);
  }

  static const int supportedVersion = 1;
  static const String audioRoot = 'assets/audio/';
  static const String manifestAssetPath = '${audioRoot}manifest.json';

  /// Loads the manifest from the asset bundle.
  static Future<ClipManifest> load(AssetBundle bundle) async =>
      ClipManifest.fromJson(await bundle.loadString(manifestAssetPath));

  final Map<String, String> _clips;

  Iterable<String> get keys => _clips.keys;

  /// A copy with [extra] clips added, for debug-only local files.
  ClipManifest withClips(Map<String, String> extra) =>
      ClipManifest(<String, String>{..._clips, ...extra});

  bool contains(String key) => _clips.containsKey(key);

  /// Resolves [keys] to full asset paths, preserving order. Unknown keys are
  /// skipped and appended to [missing] if it is given.
  List<String> resolve(List<String> keys, {List<String>? missing}) {
    final List<String> paths = <String>[];
    for (final String key in keys) {
      final String? file = _clips[key];
      if (file == null) {
        missing?.add(key);
      } else {
        paths.add('$audioRoot$file');
      }
    }
    return paths;
  }
}
