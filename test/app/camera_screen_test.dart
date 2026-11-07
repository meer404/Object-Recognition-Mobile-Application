import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/app_controller.dart';
import 'package:kurdish_vision/app/app_theme.dart';
import 'package:kurdish_vision/app/camera_screen.dart';
import 'package:kurdish_vision/app/debug_overlay.dart';
import 'package:kurdish_vision/app/sorani_localizations.dart';
import 'package:kurdish_vision/app/ui_strings.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/camera/camera_service.dart';
import 'package:kurdish_vision/detection/object_detector.dart';
import 'package:kurdish_vision/settings/settings_screen.dart';

import '../support/fakes.dart';

/// Longer than the double-tap wait, so a single tap has been recognised.
const Duration _pastDoubleTapWindow = Duration(milliseconds: 400);

void main() {
  late FakeCameraService camera;
  late FakeHaptics haptics;
  late int repeats;
  late AppController app;
  Future<void> Function()? prepare;
  ValueNotifier<DetectionOutput?>? overlayOutput;

  setUp(() {
    camera = FakeCameraService();
    haptics = FakeHaptics();
    repeats = 0;
    prepare = null;
    overlayOutput = null;
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // Built here, not in setUp, so its futures run in the tester's fake zone.
    app = AppController(
      camera: camera,
      haptics: haptics,
      setKeepAwake: (bool on) async {},
      onRepeat: () => repeats++,
      onFrame: (CameraFrame frame) async {},
      prepare: prepare,
      detectionOutput: overlayOutput,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: soraniLocale,
        supportedLocales: const <Locale>[soraniLocale],
        localizationsDelegates: soraniLocalizationsDelegates,
        home: CameraScreen(controller: app),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> doubleTap(WidgetTester tester) async {
    await tester.tap(find.byType(CameraScreen));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(CameraScreen));
    await tester.pumpAndSettle();
  }

  group('gestures', () {
    testWidgets('tap repeats', (WidgetTester tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byType(CameraScreen));
      await tester.pump(_pastDoubleTapWindow);
      await tester.pumpAndSettle();
      expect(repeats, 1);
    });

    testWidgets('double tap pauses, not repeats, then resumes', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await doubleTap(tester);
      expect(app.status, AppStatus.paused);
      expect(repeats, 0);

      await doubleTap(tester);
      expect(app.status, AppStatus.running);
    });

    testWidgets('long press opens settings, paused; back resumes', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await tester.longPress(find.byType(CameraScreen));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(app.status, AppStatus.paused);

      await tester.tap(find.byTooltip(UiStrings.back));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(app.status, AppStatus.running);
    });

    testWidgets('a user pause stays paused after settings', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await doubleTap(tester);
      await tester.longPress(find.byType(CameraScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(UiStrings.back));
      await tester.pumpAndSettle();
      expect(app.status, AppStatus.paused);
    });
  });

  group('leaving with Back', () {
    // On the Infinix X690B, Back closed the activity while the camera still
    // delivered frames, and one arriving after the engine detached crashed the
    // app ("FlutterJNI is not attached to native"). The camera must be released
    // first, and only then the app closed.
    late List<String> platformCalls;

    setUp(() {
      platformCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            platformCalls.add(call.method);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('releases the camera before the app closes', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      bool? cameraOpenWhenClosing;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            platformCalls.add(call.method);
            if (call.method == 'SystemNavigator.pop') {
              cameraOpenWhenClosing = camera.open;
            }
            return null;
          });

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(platformCalls, contains('SystemNavigator.pop'));
      expect(cameraOpenWhenClosing, isFalse, reason: 'released first');
      expect(camera.calls, contains('release'));
    });

    testWidgets('Back inside settings only closes settings', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      await tester.longPress(find.byType(CameraScreen));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsNothing);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(app.status, AppStatus.running);
      expect(camera.open, isTrue);
    });
  });

  group('gesture safety', () {
    testWidgets('a repeated long press opens settings once, camera paused', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);
      // Two long-press actions back to back, as a screen reader can deliver.
      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(UiStrings.running),
      );
      node.owner!.performAction(node.id, SemanticsAction.longPress);
      node.owner!.performAction(node.id, SemanticsAction.longPress);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(app.status, AppStatus.paused);

      await tester.tap(find.byTooltip(UiStrings.back));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(app.status, AppStatus.running);
      handle.dispose();
    });

    testWidgets('a tap while paused says it is paused', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);
      await doubleTap(tester);
      tester.takeAnnouncements();

      await tester.tap(find.byType(CameraScreen));
      await tester.pump(_pastDoubleTapWindow);
      await tester.pumpAndSettle();
      expect(
        tester.takeAnnouncements().map(
          (CapturedAccessibilityAnnouncement a) => a.message,
        ),
        <String>[UiStrings.paused],
      );
      expect(app.status, AppStatus.paused);
      handle.dispose();
    });
  });

  group('screen', () {
    testWidgets('shows the preview only when the camera is usable', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester);
      expect(find.byKey(const Key('fake-preview')), findsOneWidget);
      expect(find.text(UiStrings.running), findsNothing);

      camera.initializeError = const CameraServiceException(
        CameraFailure.noCamera,
      );
      await app.start();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fake-preview')), findsNothing);
      expect(find.text(UiStrings.noCamera), findsOneWidget);
    });

    testWidgets('each failure shows its own Sorani message', (
      WidgetTester tester,
    ) async {
      camera.initializeError = const CameraServiceException(
        CameraFailure.permissionDenied,
      );
      await pumpScreen(tester);
      expect(find.text(UiStrings.permissionDenied), findsOneWidget);

      camera.initializeError = const CameraServiceException(
        CameraFailure.other,
      );
      await app.start();
      await tester.pumpAndSettle();
      expect(find.text(UiStrings.cameraError), findsOneWidget);
    });

    testWidgets('a model failure explains itself and offers retry', (
      WidgetTester tester,
    ) async {
      Object? failure = StateError('no model');
      prepare = () async {
        final Object? current = failure;
        if (current != null) throw current;
      };
      await pumpScreen(tester);
      expect(find.text(UiStrings.modelError), findsOneWidget);
      expect(find.byKey(const Key('fake-preview')), findsNothing);

      failure = null;
      await tester.tap(find.byType(CameraScreen));
      await tester.pump(_pastDoubleTapWindow);
      await tester.pumpAndSettle();
      expect(app.status, AppStatus.running);
    });

    testWidgets('the debug overlay is off by default', (
      WidgetTester tester,
    ) async {
      overlayOutput = ValueNotifier<DetectionOutput?>(null);
      await pumpScreen(tester);
      expect(find.byType(DebugOverlay), findsNothing);

      app.updateSettings(app.settings.copyWith(showDebugOverlay: true));
      await tester.pumpAndSettle();
      expect(find.byType(DebugOverlay), findsOneWidget);
    });

    testWidgets('tap retries after a failure', (WidgetTester tester) async {
      camera.initializeError = const CameraServiceException(
        CameraFailure.permissionDenied,
      );
      await pumpScreen(tester);
      await tester.tap(find.byType(CameraScreen));
      await tester.pump(_pastDoubleTapWindow);
      await tester.pumpAndSettle();
      expect(app.status, AppStatus.running);
      expect(repeats, 0);
    });
  });

  group('screen reader', () {
    SemanticsNode node(WidgetTester tester, String label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    /// Named custom actions. Tap and long-press hints share this list as
    /// override entries with no label, so those are skipped.
    List<CustomSemanticsAction> namedActions(SemanticsData data) =>
        (data.customSemanticsActionIds ?? <int>[])
            .map(CustomSemanticsAction.getAction)
            .whereType<CustomSemanticsAction>()
            .where((CustomSemanticsAction a) => a.label != null)
            .toList();

    testWidgets('exposes the status, actions and their Sorani names', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);

      final SemanticsData data = node(
        tester,
        UiStrings.running,
      ).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(data.hasAction(SemanticsAction.customAction), isTrue);
      final SemanticsHintOverrides? hints = node(
        tester,
        UiStrings.running,
      ).hintOverrides;
      expect(hints?.onTapHint, UiStrings.repeatAction);
      expect(hints?.onLongPressHint, UiStrings.settings);
      expect(
        namedActions(data).map((CustomSemanticsAction a) => a.label),
        <String>[UiStrings.pauseAction],
      );
      handle.dispose();
    });

    testWidgets('the activate action repeats without any wait', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);
      tester.semantics.tap(find.semantics.byLabel(UiStrings.running));
      await tester.pumpAndSettle();
      expect(repeats, 1);
      handle.dispose();
    });

    testWidgets('the custom action pauses, and its name then says resume', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);

      final SemanticsData data = node(
        tester,
        UiStrings.running,
      ).getSemanticsData();
      final int id = CustomSemanticsAction.getIdentifier(
        namedActions(data).single,
      );
      final SemanticsNode runningNode = node(tester, UiStrings.running);
      runningNode.owner!.performAction(
        runningNode.id,
        SemanticsAction.customAction,
        id,
      );
      await tester.pumpAndSettle();
      expect(app.status, AppStatus.paused);

      final SemanticsData paused = node(
        tester,
        UiStrings.paused,
      ).getSemanticsData();
      expect(namedActions(paused).single.label, UiStrings.resumeAction);
      handle.dispose();
    });

    testWidgets('no pause action when there is nothing to pause', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      camera.initializeError = const CameraServiceException(
        CameraFailure.noCamera,
      );
      await pumpScreen(tester);
      final SemanticsData data = node(
        tester,
        UiStrings.noCamera,
      ).getSemanticsData();
      expect(data.hasAction(SemanticsAction.customAction), isFalse);
      expect(
        node(tester, UiStrings.noCamera).hintOverrides?.onTapHint,
        UiStrings.retryAction,
      );
      handle.dispose();
    });

    testWidgets('status changes are announced in Sorani', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);
      tester.takeAnnouncements();

      await doubleTap(tester);
      expect(
        tester.takeAnnouncements().map(
          (CapturedAccessibilityAnnouncement a) => a.message,
        ),
        <String>[UiStrings.paused],
      );
      handle.dispose();
    });

    testWidgets('meets tap-target, contrast and labelling guidelines', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      camera.initializeError = const CameraServiceException(
        CameraFailure.permissionDenied,
      );
      await pumpScreen(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('settings: labelled controls, Sorani back button', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpScreen(tester);
      await tester.longPress(find.byType(CameraScreen));
      await tester.pumpAndSettle();

      expect(find.byTooltip(UiStrings.back), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
