import 'dart:ui' show Rect;

import '../settings/app_settings.dart';

/// Coarse horizontal position of an object relative to the user.
enum HorizontalPosition {
  left,
  center,
  right;

  /// Classifies a normalized box centre x (0–1) using the settings' regions.
  static HorizontalPosition fromCenterX(double x, AppSettings settings) {
    if (x < settings.leftRegionEnd) return HorizontalPosition.left;
    if (x >= settings.rightRegionStart) return HorizontalPosition.right;
    return HorizontalPosition.center;
  }
}

/// One detected object in one frame.
class DetectionResult {
  const DetectionResult({
    required this.classId,
    required this.confidence,
    required this.box,
    required this.position,
  });

  /// Index into the model's label list (see kurdish_labels.dart).
  final int classId;

  /// Model confidence, 0–1. This is never presented to the user as certainty.
  final double confidence;

  /// Bounding box in normalized image coordinates (0–1, upright frame).
  final Rect box;

  final HorizontalPosition position;

  /// Box area as a fraction of the frame. Used as a proxy for proximity.
  double get relativeArea => box.width * box.height;

  /// Priority used to order objects in a sentence (confidence × box size).
  double get priority => confidence * relativeArea;

  @override
  bool operator ==(Object other) =>
      other is DetectionResult &&
      other.classId == classId &&
      other.confidence == confidence &&
      other.box == box &&
      other.position == position;

  @override
  int get hashCode => Object.hash(classId, confidence, box, position);

  @override
  String toString() =>
      'DetectionResult(class: $classId, conf: '
      '${confidence.toStringAsFixed(2)}, pos: ${position.name}, box: $box)';
}
