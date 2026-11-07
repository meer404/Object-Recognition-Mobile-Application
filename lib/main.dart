import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'accessibility/haptics.dart';
import 'app/app_controller.dart';
import 'app/app_theme.dart';
import 'app/camera_screen.dart';
import 'app/recognition_pipeline.dart';
import 'app/sorani_localizations.dart';
import 'app/ui_strings.dart';
import 'camera/plugin_camera_service.dart';
import 'detection/yolo_detector.dart';
import 'metrics/csv_metrics_logger.dart';
import 'metrics/evaluation_recorder.dart';
import 'metrics/metrics_logger.dart';
import 'metrics/platform_metrics.dart';
import 'settings/app_settings.dart';
import 'speech/audio_clip_speech.dart';
import 'speech/kurdish_labels.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only, so left and right in the image match the user's (D-017).
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  runApp(const KurdishVisionApp(createController: _createController));
}

AppController _createController() {
  const AppSettings settings = AppSettings();
  final String modelAsset =
      'assets/models/yolo26n_${settings.modelInputSize}_fp32.tflite';
  int? modelBytes;
  late final AppController controller;

  final YoloDetector detector = YoloDetector(
    settings: settings,
    allowedClasses: kurdishLabels.keys.toSet(),
    loadModelBytes: () async {
      final ByteData data = await rootBundle.load(modelAsset);
      modelBytes = data.lengthInBytes;
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    },
  );

  final EvaluationRecorder recorder = EvaluationRecorder(
    logger: CsvMetricsLogger(
      root: metricsRoot,
      flushInterval: settings.metricsFlushInterval,
    ),
    probe: PlatformDeviceProbe(),
    counts: () => SchedulerCounts(
      accepted: controller.scheduler.acceptedCount,
      droppedBusy: controller.scheduler.droppedBusyCount,
      droppedRate: controller.scheduler.droppedRateCount,
    ),
    sessionInfo: () async {
      final (String device, String os) = await deviceDescription();
      return SessionInfo(
        startedAt: DateTime.now(),
        buildMode: currentBuildMode(),
        appVersion: await appVersion(),
        gitCommit: buildGitCommit,
        device: device,
        os: os,
        accelerator: detector.accelerator ?? 'not loaded',
        modelAsset: modelAsset,
        modelBytes: modelBytes,
        settings: controller.settings.toJson(),
      );
    },
  );

  final RecognitionPipeline pipeline = RecognitionPipeline(
    settings: settings,
    speech: AudioClipSpeech.standard(),
    detector: detector,
    onMetrics: recorder.logFrame,
  );
  controller = AppController(
    settings: settings,
    camera: PluginCameraService(quality: settings.cameraQuality),
    haptics: const PlatformHaptics(),
    setKeepAwake: (bool enabled) => WakelockPlus.toggle(enable: enabled),
    onFrame: pipeline.processFrame,
    onRepeat: pipeline.repeat,
    prepare: pipeline.load,
    onStopped: () {
      pipeline.reset();
      unawaited(recorder.flush());
    },
    onSettingsChanged: (AppSettings value) {
      pipeline.updateSettings(value);
      unawaited(recorder.apply(value));
    },
    onDispose: () async {
      await pipeline.dispose();
      await recorder.dispose();
    },
    detectionOutput: pipeline.latestOutput,
    exportMetrics: () async {
      final List<String> files = await recorder.exportFiles();
      if (files.isEmpty) return false;
      await shareFiles(files);
      return true;
    },
  );
  pipeline.onDetectorLost = controller.reportDetectorLost;
  return controller;
}

/// Root widget: Sorani locale, RTL, high-contrast theme.
class KurdishVisionApp extends StatefulWidget {
  const KurdishVisionApp({super.key, required this.createController});

  final AppController Function() createController;

  @override
  State<KurdishVisionApp> createState() => _KurdishVisionAppState();
}

class _KurdishVisionAppState extends State<KurdishVisionApp> {
  late final AppController _controller = widget.createController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: UiStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: soraniLocale,
      supportedLocales: const <Locale>[soraniLocale],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        ...soraniLocalizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      // Belt and braces: the UI is RTL even if locale resolution changes.
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: CameraScreen(controller: _controller),
    );
  }
}
