import 'package:flutter/services.dart';

/// Haptic feedback for state changes (start/stop, pause/resume).
///
/// Behind an interface so tests can verify calls without a device.
abstract class Haptics {
  Future<void> started();
  Future<void> stopped();

  /// A light confirmation that a gesture was received.
  Future<void> tick();
}

/// [Haptics] using the system's haptic feedback. Start and stop differ in
/// strength so they can be told apart by touch.
class PlatformHaptics implements Haptics {
  const PlatformHaptics();

  @override
  Future<void> started() => HapticFeedback.mediumImpact();

  @override
  Future<void> stopped() => HapticFeedback.heavyImpact();

  @override
  Future<void> tick() => HapticFeedback.selectionClick();
}
