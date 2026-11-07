import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../accessibility/accessibility_controls.dart';
import '../settings/settings_screen.dart';
import 'app_controller.dart';
import 'debug_overlay.dart';
import 'ui_strings.dart';

/// The main screen: a full-screen camera preview controlled by whole-screen
/// gestures. Tap = repeat, double tap = pause/resume, long press = settings.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  AppController get _app => widget.controller;
  late AppStatus _announcedStatus = _app.status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app.addListener(_onAppChanged);
    unawaited(_app.start());
  }

  @override
  void dispose() {
    _app.removeListener(_onAppChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _app.handleLifecycle(state);
  }

  void _onAppChanged() {
    final AppStatus status = _app.status;
    if (status == _announcedStatus) return;
    _announcedStatus = status;
    if (status != AppStatus.initializing) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _statusText(status),
          TextDirection.rtl,
        ),
      );
    }
  }

  /// Pauses while settings are open, so speech cannot talk over them.
  ///
  /// A second long press while this runs is ignored. Otherwise both would see
  /// "running", the second toggle would resume the camera behind settings, and
  /// two settings pages would stack (a screen reader can repeat the action).
  Future<void> _openSettings() async {
    if (_openingSettings) return;
    _openingSettings = true;
    try {
      final bool wasRunning = _app.status == AppStatus.running;
      if (wasRunning) await _app.togglePause();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(controller: _app),
        ),
      );
      if (wasRunning && _app.status == AppStatus.paused) {
        await _app.togglePause();
      }
    } finally {
      _openingSettings = false;
    }
  }

  bool _openingSettings = false;

  /// While paused a tap repeats nothing, so it says why instead of doing
  /// nothing (a silent tap feels like a frozen app).
  void _onTap() {
    if (_app.status == AppStatus.paused) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          UiStrings.paused,
          TextDirection.rtl,
        ),
      );
    }
    unawaited(_app.primaryAction());
  }

  static String _statusText(AppStatus status) => switch (status) {
    AppStatus.initializing => UiStrings.preparing,
    AppStatus.running => UiStrings.running,
    AppStatus.paused => UiStrings.paused,
    AppStatus.permissionDenied => UiStrings.permissionDenied,
    AppStatus.noCamera => UiStrings.noCamera,
    AppStatus.error => UiStrings.cameraError,
    AppStatus.modelError => UiStrings.modelError,
  };

  static String? _tapHint(AppStatus status) => switch (status) {
    AppStatus.running => UiStrings.repeatAction,
    AppStatus.permissionDenied ||
    AppStatus.noCamera ||
    AppStatus.error ||
    AppStatus.modelError => UiStrings.retryAction,
    AppStatus.initializing || AppStatus.paused => null,
  };

  static String? _pauseLabel(AppStatus status) => switch (status) {
    AppStatus.running => UiStrings.pauseAction,
    AppStatus.paused => UiStrings.resumeAction,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _app,
      builder: (BuildContext context, Widget? _) {
        final AppStatus status = _app.status;
        // Back on this screen closes the app. Release the camera first: closing
        // while it streams crashed on a real phone (D-024).
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? _) {
            if (!didPop) unawaited(_exitApp());
          },
          child: Scaffold(
            body: AccessibilityControls(
              label: _statusText(status),
              tapHint: _tapHint(status),
              doubleTapLabel: _pauseLabel(status),
              longPressHint: UiStrings.settings,
              onTap: _onTap,
              onDoubleTap: () => unawaited(_app.togglePause()),
              onLongPress: () => unawaited(_openSettings()),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (_app.showPreview) _app.camera.buildPreview(),
                  if (_app.showPreview &&
                      _app.settings.showDebugOverlay &&
                      _app.detectionOutput != null)
                    DebugOverlay(output: _app.detectionOutput!),
                  // While running the preview speaks for itself; a label over it
                  // could also be read as a claim about what is in view.
                  if (status != AppStatus.running)
                    Center(
                      child: Container(
                        color: Colors.black,
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _statusText(status),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Releases the camera, then closes the app (Android finishes the activity).
  Future<void> _exitApp() async {
    await _app.prepareToExit();
    await SystemNavigator.pop();
  }
}
