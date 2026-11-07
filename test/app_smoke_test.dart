import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/app_controller.dart';
import 'package:kurdish_vision/app/sorani_localizations.dart';
import 'package:kurdish_vision/app/ui_strings.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/main.dart';

import 'support/fakes.dart';

final List<FakeCameraService> _cameras = <FakeCameraService>[];

AppController _controller() => AppController(
  camera: (FakeCameraService()..also(_cameras.add)),
  haptics: FakeHaptics(),
  setKeepAwake: (bool on) async {},
  onFrame: (CameraFrame frame) async {},
);

extension on FakeCameraService {
  void also(void Function(FakeCameraService) use) => use(this);
}

/// Closes the app and runs the camera cleanup it queues.
Future<void> _closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('app builds with Sorani locale and RTL direction', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const KurdishVisionApp(createController: _controller),
    );
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(Scaffold));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(Localizations.localeOf(context), soraniLocale);
    // Framework strings resolve through the ckb → ar fallback delegate.
    expect(MaterialLocalizations.of(context), isNotNull);
    await _closeApp(tester);
  });

  testWidgets('the camera starts when the app opens', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const KurdishVisionApp(createController: _controller),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(UiStrings.running), findsOneWidget);
    await _closeApp(tester);
    expect(_cameras.last.calls.last, 'dispose');
    handle.dispose();
  });
}
