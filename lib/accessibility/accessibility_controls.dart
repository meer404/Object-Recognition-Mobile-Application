import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Whole-screen controls: single tap, double tap and long press.
///
/// A screen reader consumes raw gestures, so each action is also exposed
/// through semantics. Its "activate" gesture runs [onTap], its long-press
/// gesture runs [onLongPress], and [onDoubleTap] is a named custom action
/// (TalkBack's actions menu, VoiceOver's rotor).
class AccessibilityControls extends StatelessWidget {
  const AccessibilityControls({
    super.key,
    required this.label,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.child,
    this.tapHint,
    this.doubleTapLabel,
    this.longPressHint,
  });

  /// What the screen reader says when the screen gets focus.
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onLongPress;
  final Widget child;

  /// Name of the tap action, or null to leave it unnamed.
  final String? tapHint;

  /// Name of the double-tap action. Null hides it when it does nothing.
  final String? doubleTapLabel;

  /// Name of the long-press action.
  final String? longPressHint;

  @override
  Widget build(BuildContext context) {
    final String? doubleTapName = doubleTapLabel;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: label,
      onTap: onTap,
      onTapHint: tapHint,
      onLongPress: onLongPress,
      onLongPressHint: longPressHint,
      customSemanticsActions: doubleTapName == null
          ? null
          : <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(label: doubleTapName): onDoubleTap,
            },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: child,
      ),
    );
  }
}
