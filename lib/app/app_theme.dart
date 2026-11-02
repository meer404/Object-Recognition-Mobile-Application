import 'package:flutter/material.dart';

/// High-contrast theme for low-vision users.
abstract final class AppTheme {
  /// Minimum touch target, in logical pixels (CLAUDE.md: ≥ 48 dp).
  static const double minTouchTarget = 48;

  static ThemeData get dark {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: Brightness.dark,
      contrastLevel: 1.0,
    );
    const Size minSize = Size(minTouchTarget, minTouchTarget);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: Typography.whiteMountainView.apply(fontSizeFactor: 1.3),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: minSize),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: minSize),
      ),
    );
  }
}
