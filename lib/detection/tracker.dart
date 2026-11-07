import '../settings/app_settings.dart';
import 'detection_filter.dart';
import 'detection_result.dart';

/// Decides which confirmed objects are worth announcing now.
///
/// An object is (re-)announced only if it is new, disappeared and came back
/// (the filter then gives it a new track), changed position (left/center/
/// right), or its [AppSettings.repeatCooldown] expired. The user's Repeat
/// gesture is handled by the pipeline, which speaks straight away.
///
/// Asking does not consume anything: an object counts as announced only after
/// [markAnnounced], so one that could not be spoken yet stays due.
class Tracker {
  Tracker({required this.settings});

  AppSettings settings;

  final Map<int, _Announced> _announced = <int, _Announced>{};

  /// Returns the objects in [result] that are due at [now].
  List<TrackedDetection> objectsToAnnounce(FilterResult result, DateTime now) {
    _announced.removeWhere(
      (int id, _Announced _) => !result.liveTrackIds.contains(id),
    );
    return <TrackedDetection>[
      for (final TrackedDetection object in result.confirmed)
        if (_isDue(object, now)) object,
    ];
  }

  /// Records that [objects] were just spoken.
  void markAnnounced(Iterable<TrackedDetection> objects, DateTime now) {
    for (final TrackedDetection object in objects) {
      _announced[object.trackId] = _Announced(now, object.detection.position);
    }
  }

  /// Forgets all tracked objects.
  void reset() => _announced.clear();

  bool _isDue(TrackedDetection object, DateTime now) {
    final _Announced? last = _announced[object.trackId];
    if (last == null) return true;
    if (last.position != object.detection.position) return true;
    return now.difference(last.at) >= settings.repeatCooldown;
  }
}

class _Announced {
  const _Announced(this.at, this.position);

  final DateTime at;
  final HorizontalPosition position;
}
