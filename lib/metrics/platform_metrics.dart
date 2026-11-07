import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'evaluation_recorder.dart';

/// Real [DeviceProbe]. RSS is the whole process, including native memory such
/// as the model and camera buffers, as the OS reports it.
class PlatformDeviceProbe implements DeviceProbe {
  PlatformDeviceProbe() : _battery = Battery();

  final Battery _battery;

  @override
  int rssBytes() => ProcessInfo.currentRss;

  @override
  Future<int?> batteryPercent() => _battery.batteryLevel;

  @override
  Future<String> batteryState() async => (await _battery.batteryState).name;
}

/// The app documents directory (CLAUDE.md: CSV in app documents dir).
Future<Directory> metricsRoot() => getApplicationDocumentsDirectory();

/// `debug`, `profile` or `release`.
String currentBuildMode() => kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

/// The commit the app was built from: pass
/// `--dart-define=GIT_COMMIT=$(git rev-parse HEAD)` when building.
const String buildGitCommit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: 'unknown (build without --dart-define=GIT_COMMIT)',
);

/// App version as `version+build`, or `unknown`.
Future<String> appVersion() async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return 'unknown';
  }
}

/// Device model and OS version, or `unknown`.
Future<(String device, String os)> deviceDescription() async {
  try {
    final DeviceInfoPlugin info = DeviceInfoPlugin();
    if (!kIsWeb && Platform.isAndroid) {
      final AndroidDeviceInfo a = await info.androidInfo;
      return (
        '${a.manufacturer} ${a.model}',
        'Android ${a.version.release} (API ${a.version.sdkInt})',
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      final IosDeviceInfo i = await info.iosInfo;
      return (i.modelName, 'iOS ${i.systemVersion}');
    }
  } catch (_) {
    // Fall through.
  }
  return (
    'unknown',
    kIsWeb ? 'web' : '${Platform.operatingSystem} unknown version',
  );
}

/// Opens the system share sheet with [paths]. The user chooses where the files
/// go; the app itself sends nothing over the network.
Future<void> shareFiles(List<String> paths) async {
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[for (final String p in paths) XFile(p)],
      subject: 'kurdish_vision evaluation session',
    ),
  );
}
