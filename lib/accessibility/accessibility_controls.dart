import 'package:flutter/widgets.dart';

/// Whole-screen gesture layer (Phase 2).
///
/// Defaults (configurable): single tap = repeat, double tap = pause/resume,
/// long press = settings. Every action gets a Sorani Semantics label and a
/// custom semantics action so it works with TalkBack and VoiceOver.
///
/// Phase 0: passes [child] through unchanged.
class AccessibilityControls extends StatelessWidget {
  const AccessibilityControls({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
