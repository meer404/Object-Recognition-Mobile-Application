import 'dart:async';
import 'dart:io';

import 'metrics_logger.dart';

/// [MetricsLogger] writing one folder per session under `<root>/metrics/`:
/// `session.json`, `frames.csv` and `device.csv`.
///
/// Rows are buffered and appended every [flushInterval], and on [flush] and
/// [stop], so a crash loses at most one interval. No images are ever written.
class CsvMetricsLogger implements MetricsLogger {
  CsvMetricsLogger({
    required Future<Directory> Function() root,
    required this.flushInterval,
    DateTime Function()? now,
  }) : _root = root,
       _now = now ?? DateTime.now;

  static const String sessionFile = 'session.json';
  static const String framesFile = 'frames.csv';
  static const String deviceFile = 'device.csv';
  static const List<String> files = <String>[
    sessionFile,
    framesFile,
    deviceFile,
  ];

  final Future<Directory> Function() _root;
  final Duration flushInterval;
  final DateTime Function() _now;

  Directory? _session;
  Directory? _lastSession;
  StringBuffer _frames = StringBuffer();
  StringBuffer _device = StringBuffer();
  Timer? _timer;

  /// Disk writes happen one at a time, in order.
  Future<void> _writes = Future<void>.value();

  @override
  bool get isActive => _session != null;

  @override
  Future<String> start(SessionInfo info) async {
    if (isActive) await stop();
    final Directory metrics = Directory(
      '${(await _root()).path}${Platform.pathSeparator}metrics',
    );
    final Directory session = await _newSessionFolder(metrics);
    await File(_path(session, sessionFile)).writeAsString(info.toPrettyJson());
    await File(_path(session, framesFile)).writeAsString('$frameCsvHeader\n');
    await File(_path(session, deviceFile)).writeAsString('$deviceCsvHeader\n');
    _session = session;
    _lastSession = session;
    _timer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
    return session.path;
  }

  @override
  void logFrame(FrameMetrics metrics) {
    if (isActive) _frames.writeln(frameCsvRow(metrics));
  }

  @override
  void logDevice(DeviceSample sample) {
    if (isActive) _device.writeln(deviceCsvRow(sample));
  }

  @override
  Future<void> flush() {
    final Directory? session = _session;
    if (session == null) return _writes;
    final String frames = _frames.toString();
    final String device = _device.toString();
    _frames = StringBuffer();
    _device = StringBuffer();
    return _writes = _writes.then((_) async {
      if (frames.isNotEmpty) {
        await File(
          _path(session, framesFile),
        ).writeAsString(frames, mode: FileMode.append, flush: true);
      }
      if (device.isNotEmpty) {
        await File(
          _path(session, deviceFile),
        ).writeAsString(device, mode: FileMode.append, flush: true);
      }
    });
  }

  @override
  Future<List<String>> stop() async {
    final Directory? session = _session;
    if (session == null) return const <String>[];
    _timer?.cancel();
    _timer = null;
    await flush();
    _session = null;
    return _filesOf(session);
  }

  @override
  Future<List<String>> latestSessionFiles() async {
    if (isActive) await flush();
    final Directory? known = _session ?? _lastSession;
    if (known != null) return _filesOf(known);
    // After a restart: the newest folder on disk. Names sort by time.
    final Directory metrics = Directory(
      '${(await _root()).path}${Platform.pathSeparator}metrics',
    );
    if (!metrics.existsSync()) return const <String>[];
    final List<Directory> sessions =
        metrics
            .listSync()
            .whereType<Directory>()
            .where((Directory d) => File(_path(d, sessionFile)).existsSync())
            .toList()
          ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
    return sessions.isEmpty ? const <String>[] : _filesOf(sessions.last);
  }

  Future<Directory> _newSessionFolder(Directory metrics) async {
    final String stamp = sessionStamp(_now());
    Directory folder = Directory(_path(metrics, stamp));
    for (int i = 2; folder.existsSync(); i++) {
      folder = Directory(_path(metrics, '$stamp-$i'));
    }
    return folder.create(recursive: true);
  }

  static List<String> _filesOf(Directory session) => <String>[
    for (final String name in files) _path(session, name),
  ];

  static String _path(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';
}

/// Folder name for a session started at [time]: sortable and valid on every
/// file system, e.g. `20261108T143005Z`.
String sessionStamp(DateTime time) {
  final DateTime t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}'
      'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}
