import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/app_controller.dart';
import 'package:kurdish_vision/app/app_theme.dart';
import 'package:kurdish_vision/app/sorani_localizations.dart';
import 'package:kurdish_vision/app/ui_strings.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/settings/app_settings.dart';
import 'package:kurdish_vision/settings/settings_screen.dart';

import '../support/fakes.dart';

void main() {
  late List<AppSettings> applied;
  late bool hasSession;
  late int exports;

  Future<AppController> pump(
    WidgetTester tester, {
    bool withExport = true,
  }) async {
    final AppController controller = AppController(
      camera: FakeCameraService(),
      haptics: FakeHaptics(),
      setKeepAwake: (bool on) async {},
      onFrame: (CameraFrame frame) async {},
      onSettingsChanged: applied.add,
      exportMetrics: withExport
          ? () async {
              exports++;
              return hasSession;
            }
          : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: soraniLocale,
        supportedLocales: const <Locale>[soraniLocale],
        localizationsDelegates: soraniLocalizationsDelegates,
        home: SettingsScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  setUp(() {
    applied = <AppSettings>[];
    hasSession = true;
    exports = 0;
  });

  testWidgets('evaluation mode is off by default and can be turned on', (
    WidgetTester tester,
  ) async {
    final AppController controller = await pump(tester);
    expect(controller.settings.evaluationMode, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isFalse,
    );

    await tester.tap(find.text(UiStrings.evaluationMode));
    await tester.pumpAndSettle();
    expect(controller.settings.evaluationMode, isTrue);
    expect(applied.single.evaluationMode, isTrue);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isTrue,
    );
  });

  testWidgets('the switch reads as a Sorani toggle to a screen reader', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(find.byType(SwitchListTile).first),
      isSemantics(
        label: '${UiStrings.evaluationMode}\n${UiStrings.evaluationModeDetail}',
        hasToggledState: true,
        isToggled: false,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('export shares the session', (WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text(UiStrings.exportMetrics));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(find.text(UiStrings.noMetrics), findsNothing);
  });

  testWidgets('export says so when there is nothing to share', (
    WidgetTester tester,
  ) async {
    hasSession = false;
    await pump(tester);
    await tester.tap(find.text(UiStrings.exportMetrics));
    await tester.pumpAndSettle();
    expect(find.text(UiStrings.noMetrics), findsOneWidget);
  });

  testWidgets('no export button without an exporter', (
    WidgetTester tester,
  ) async {
    await pump(tester, withExport: false);
    expect(find.text(UiStrings.exportMetrics), findsNothing);
  });

  testWidgets('meets tap-target, labelling and contrast guidelines', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
