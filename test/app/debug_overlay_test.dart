import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/debug_overlay.dart';

void main() {
  const Rect whole = Rect.fromLTRB(0, 0, 1, 1);

  test('an image of the same shape fills the screen', () {
    final Rect r = DebugOverlayPainter.mapBox(
      whole,
      const Size(300, 400),
      600,
      800,
    );
    expect(r, const Rect.fromLTRB(0, 0, 300, 400));
  });

  test('a wider image is cropped at the sides, like BoxFit.cover', () {
    final Rect r = DebugOverlayPainter.mapBox(
      whole,
      const Size(300, 400),
      400,
      400,
    );
    expect(r, const Rect.fromLTRB(-50, 0, 350, 400));
  });

  test('a taller image is cropped at the top and bottom', () {
    final Rect r = DebugOverlayPainter.mapBox(
      whole,
      const Size(400, 400),
      300,
      600,
    );
    expect(r, const Rect.fromLTRB(0, -200, 400, 600));
  });

  test('a box lands at its proportional place', () {
    final Rect r = DebugOverlayPainter.mapBox(
      const Rect.fromLTRB(0.5, 0.5, 1, 1),
      const Size(300, 400),
      600,
      800,
    );
    expect(r, const Rect.fromLTRB(150, 200, 300, 400));
  });
}
