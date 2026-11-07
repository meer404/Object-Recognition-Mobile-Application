import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('library permissions the app must not have are removed (D-018)', () {
    for (final String permission in <String>[
      'RECORD_AUDIO',
      'WRITE_EXTERNAL_STORAGE',
      'READ_EXTERNAL_STORAGE',
    ]) {
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.$permission" '
          'tools:node="remove" />',
        ),
        reason: permission,
      );
    }
  });

  test('the app declares the camera permission', () {
    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.CAMERA" />'),
    );
  });

  test('the main manifest does not ask for internet access', () {
    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });
}
