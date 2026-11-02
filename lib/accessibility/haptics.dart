/// Haptic feedback for state changes (start/stop, pause/resume).
///
/// Behind an interface so widget tests can verify calls without a device.
/// Implemented in Phase 2 using `HapticFeedback`.
abstract class Haptics {
  Future<void> started();
  Future<void> stopped();
}
