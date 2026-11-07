import '../settings/app_settings.dart';
import 'detection_result.dart';

/// A detection that has been followed across frames.
class TrackedDetection {
  const TrackedDetection({required this.trackId, required this.detection});

  /// Stable while the object stays in view. A returning object gets a new id.
  final int trackId;

  /// The latest detection, with its position smoothed by hysteresis.
  final DetectionResult detection;
}

/// One frame's result from [DetectionFilter.update].
class FilterResult {
  const FilterResult({required this.confirmed, required this.liveTrackIds});

  /// Objects seen in N of the last M results, including one that was briefly
  /// missed in this frame (it keeps its last box).
  final List<TrackedDetection> confirmed;

  /// Every track still within the window. An id missing from this set has
  /// really gone, as opposed to being temporarily unconfirmed.
  final Set<int> liveTrackIds;
}

/// Removes unreliable detections before they reach the tracker.
///
/// Detections below [AppSettings.confidenceThreshold] count as misses. An object
/// is confirmed once it appears in [AppSettings.confirmationHits] of the last
/// [AppSettings.confirmationWindow] results. Detections continue a track of the
/// same class by box overlap, so two chairs are two objects.
class DetectionFilter {
  DetectionFilter({required this.settings});

  AppSettings settings;

  final List<_Track> _tracks = <_Track>[];
  int _nextTrackId = 0;

  /// Feeds one frame's detections.
  FilterResult update(List<DetectionResult> detections) {
    final List<DetectionResult> reliable = <DetectionResult>[
      for (final DetectionResult d in detections)
        if (d.confidence >= settings.confidenceThreshold) d,
    ];

    final Set<_Track> matchedTracks = _match(reliable);
    for (final _Track track in _tracks) {
      track.record(hit: matchedTracks.contains(track), settings: settings);
    }
    _tracks.removeWhere((_Track t) => t.isGone);

    return FilterResult(
      confirmed: <TrackedDetection>[
        for (final _Track t in _tracks)
          if (t.hits >= settings.confirmationHits)
            TrackedDetection(trackId: t.id, detection: t.smoothed),
      ],
      liveTrackIds: <int>{for (final _Track t in _tracks) t.id},
    );
  }

  /// Clears the history (e.g. after pause/resume).
  void reset() => _tracks.clear();

  /// Greedy matching, best overlap first. Unmatched detections start new tracks.
  Set<_Track> _match(List<DetectionResult> reliable) {
    final List<_Pair> pairs = <_Pair>[];
    for (final DetectionResult d in reliable) {
      for (final _Track t in _tracks) {
        if (t.classId != d.classId) continue;
        final double overlap = _iou(d, t.latest);
        if (overlap >= settings.trackMatchIou) {
          pairs.add(_Pair(d, t, overlap));
        }
      }
    }
    pairs.sort((_Pair a, _Pair b) => b.overlap.compareTo(a.overlap));

    final Set<_Track> usedTracks = <_Track>{};
    final Set<DetectionResult> usedDetections = <DetectionResult>{};
    for (final _Pair pair in pairs) {
      if (usedTracks.contains(pair.track)) continue;
      if (usedDetections.contains(pair.detection)) continue;
      usedTracks.add(pair.track);
      usedDetections.add(pair.detection);
      pair.track.latest = pair.detection;
    }

    for (final DetectionResult d in reliable) {
      if (usedDetections.contains(d)) continue;
      final _Track track = _Track(_nextTrackId++, d);
      _tracks.add(track);
      usedTracks.add(track);
    }
    return usedTracks;
  }

  static double _iou(DetectionResult a, DetectionResult b) {
    final overlap = a.box.intersect(b.box);
    if (overlap.width <= 0 || overlap.height <= 0) return 0;
    final double intersection = overlap.width * overlap.height;
    final double union = a.relativeArea + b.relativeArea - intersection;
    return union > 0 ? intersection / union : 0;
  }
}

class _Pair {
  const _Pair(this.detection, this.track, this.overlap);

  final DetectionResult detection;
  final _Track track;
  final double overlap;
}

class _Track {
  _Track(this.id, this.latest)
    : classId = latest.classId,
      _position = latest.position;

  final int id;
  final int classId;
  DetectionResult latest;
  HorizontalPosition _position;

  /// Most recent first; true = seen in that result.
  final List<bool> _history = <bool>[];

  int get hits => _history.where((bool hit) => hit).length;
  bool get isGone => hits == 0;

  DetectionResult get smoothed => DetectionResult(
    classId: latest.classId,
    confidence: latest.confidence,
    box: latest.box,
    position: _position,
  );

  void record({required bool hit, required AppSettings settings}) {
    _history.insert(0, hit);
    if (_history.length > settings.confirmationWindow) _history.removeLast();
    if (hit) _position = _stablePosition(settings);
  }

  /// Moves to a new region only once the centre is clearly inside it, so an
  /// object near a boundary does not flip between positions.
  HorizontalPosition _stablePosition(AppSettings settings) {
    final double x = latest.box.center.dx;
    final double margin = settings.positionHysteresis;
    final HorizontalPosition below = HorizontalPosition.fromCenterX(
      x - margin,
      settings,
    );
    final HorizontalPosition above = HorizontalPosition.fromCenterX(
      x + margin,
      settings,
    );
    return below == above ? below : _position;
  }
}
