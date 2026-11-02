import '../settings/app_settings.dart';
import 'detection_result.dart';

/// Decides which confirmed objects are worth announcing now.
///
/// An object is (re-)announced only if it is new, disappeared and came
/// back, changed position (left/center/right), its
/// [AppSettings.repeatCooldown] expired, or the user pressed Repeat.
///
/// Implemented and unit-tested in Phase 3.
class Tracker {
  Tracker({required this.settings});

  final AppSettings settings;

  /// Returns the subset of [confirmed] that should be spoken at [now].
  List<DetectionResult> objectsToAnnounce(
    List<DetectionResult> confirmed,
    DateTime now,
  ) {
    throw UnimplementedError('Tracker.objectsToAnnounce — Phase 3');
  }

  /// Marks everything currently visible as due for announcement (Repeat).
  void requestRepeat() {}

  /// Forgets all tracked objects.
  void reset() {}
}
