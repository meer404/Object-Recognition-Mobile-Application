import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../settings/app_settings.dart';
import 'detection_result.dart';
import 'preprocessing.dart';

/// Number of box values before the class scores in each output channel.
const int _boxChannels = 4;

/// Decodes the raw YOLO26n output to detections.
///
/// [raw] is the `[1, channels, anchors]` tensor, flattened: `[raw[c * anchors +
/// a]]` is channel `c` of anchor `a`. Channels are centre x, centre y, width,
/// height (normalized to the model input) followed by class scores already in
/// 0–1. All D-012 exports have this raw layout, so the app must run NMS.
///
/// Results are ordered by descending confidence and limited to
/// [allowedClasses]. A class outside it can still suppress nothing: NMS is per
/// class, so filtering first only saves work.
List<DetectionResult> decodeDetections(
  Float32List raw, {
  required int channels,
  required int anchors,
  required LetterboxGeometry geometry,
  required AppSettings settings,
  required Set<int> allowedClasses,
}) {
  if (raw.length != channels * anchors) {
    throw ArgumentError(
      'output has ${raw.length} values, expected ${channels * anchors}',
    );
  }
  final int classes = channels - _boxChannels;
  final double floor = settings.candidateConfidence;
  final List<_Candidate> candidates = <_Candidate>[];
  for (int a = 0; a < anchors; a++) {
    double best = 0;
    int bestClass = -1;
    for (int c = 0; c < classes; c++) {
      final double score = raw[(c + _boxChannels) * anchors + a];
      if (score > best) {
        best = score;
        bestClass = c;
      }
    }
    if (best < floor || !allowedClasses.contains(bestClass)) continue;
    final double cx = raw[a];
    final double cy = raw[anchors + a];
    final double halfW = raw[2 * anchors + a] / 2;
    final double halfH = raw[3 * anchors + a] / 2;
    candidates.add(
      _Candidate(
        bestClass,
        best,
        cx - halfW,
        cy - halfH,
        cx + halfW,
        cy + halfH,
      ),
    );
  }
  candidates.sort((_Candidate a, _Candidate b) => b.score.compareTo(a.score));

  final List<_Candidate> kept = <_Candidate>[];
  for (final _Candidate candidate in candidates) {
    final bool suppressed = kept.any(
      (_Candidate other) =>
          other.classId == candidate.classId &&
          other.iou(candidate) > settings.nmsIouThreshold,
    );
    if (!suppressed) kept.add(candidate);
  }

  return <DetectionResult>[
    for (final _Candidate c in kept) c.toResult(geometry, settings),
  ];
}

class _Candidate {
  _Candidate(this.classId, this.score, this.x1, this.y1, this.x2, this.y2);

  final int classId;
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  double iou(_Candidate other) {
    final double width = _min(x2, other.x2) - _max(x1, other.x1);
    final double height = _min(y2, other.y2) - _max(y1, other.y1);
    if (width <= 0 || height <= 0) return 0;
    final double intersection = width * height;
    final double union =
        (x2 - x1) * (y2 - y1) +
        (other.x2 - other.x1) * (other.y2 - other.y1) -
        intersection;
    return union > 0 ? intersection / union : 0;
  }

  DetectionResult toResult(LetterboxGeometry geometry, AppSettings settings) {
    final Rect box = geometry.toUprightBox(x1, y1, x2, y2);
    return DetectionResult(
      classId: classId,
      confidence: score,
      box: box,
      position: HorizontalPosition.fromCenterX(box.center.dx, settings),
    );
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;
}
