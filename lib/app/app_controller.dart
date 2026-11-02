import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';

/// High-level app state.
enum AppStatus { initializing, running, paused, error }

/// Orchestrates the pipeline:
/// CameraStream → FrameScheduler → Detector → DetectionFilter & Tracker
/// → PhraseBuilder → SpeechOutput.
///
/// Uses ChangeNotifier (see docs/decisions.md). Wiring happens in Phase 2–3.
class AppController extends ChangeNotifier {
  AppController({this.settings = const AppSettings()});

  AppSettings settings;

  AppStatus _status = AppStatus.initializing;
  AppStatus get status => _status;

  void updateSettings(AppSettings value) {
    settings = value;
    notifyListeners();
  }

  @protected
  void setStatus(AppStatus value) {
    if (value == _status) return;
    _status = value;
    notifyListeners();
  }
}
