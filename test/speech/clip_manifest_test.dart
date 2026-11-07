import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/speech/clip_manifest.dart';

void main() {
  test('parses clips and resolves keys in order', () {
    final ClipManifest m = ClipManifest.fromJson(
      '{"version": 1, "clips": {"a": "a.m4a", "b": "sub/b.wav"}}',
    );
    expect(m.resolve(<String>['b', 'a']), <String>[
      'assets/audio/sub/b.wav',
      'assets/audio/a.m4a',
    ]);
  });

  test('unknown keys are skipped and reported', () {
    final ClipManifest m = ClipManifest.fromJson(
      '{"version": 1, "clips": {"a": "a.m4a"}}',
    );
    final List<String> missing = <String>[];
    expect(m.resolve(<String>['x', 'a', 'y'], missing: missing), <String>[
      'assets/audio/a.m4a',
    ]);
    expect(missing, <String>['x', 'y']);
  });

  test('withClips adds entries and keeps the original intact', () {
    final ClipManifest base = ClipManifest(<String, String>{'a': 'a.m4a'});
    final ClipManifest extended = base.withClips(<String, String>{
      'b': 'local/b.mp3',
    });
    expect(extended.resolve(<String>['a', 'b']), <String>[
      'assets/audio/a.m4a',
      'assets/audio/local/b.mp3',
    ]);
    expect(base.contains('b'), isFalse);
  });

  test('rejects malformed manifests', () {
    for (final String bad in <String>[
      '[]',
      '{"version": 2, "clips": {}}',
      '{"version": 1}',
      '{"version": 1, "clips": {"a": 3}}',
      '{"version": 1, "clips": {"a": ""}}',
    ]) {
      expect(
        () => ClipManifest.fromJson(bad),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('the bundled manifest parses and every file exists', () {
    final ClipManifest m = ClipManifest.fromJson(
      File(ClipManifest.manifestAssetPath).readAsStringSync(),
    );
    for (final String key in m.keys) {
      final String path = m.resolve(<String>[key]).single;
      expect(File(path).existsSync(), isTrue, reason: '$key → $path');
    }
  });
}
