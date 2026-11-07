/// Central, immutable configuration for the whole pipeline.
///
/// Every threshold used anywhere in the app lives here so that no stage
/// contains magic numbers and every experiment in the evaluation can state
/// exactly which configuration it ran with. Defaults follow CLAUDE.md.
library;

/// Camera resolution tier. The exact size depends on the device.
enum CameraQuality { low, medium, high }

/// Immutable application settings. Use [copyWith] to derive variants.
class AppSettings {
  const AppSettings({
    this.targetInferencesPerSecond = 4,
    this.confidenceThreshold = 0.5,
    this.confirmationHits = 2,
    this.confirmationWindow = 3,
    this.repeatCooldown = const Duration(seconds: 5),
    this.maxObjectsPerSentence = 3,
    this.leftRegionEnd = 1 / 3,
    this.rightRegionStart = 2 / 3,
    this.speechVolume = 1.0,
    this.speechStartTimeout = const Duration(seconds: 3),
    this.cameraQuality = CameraQuality.medium,
    this.modelInputSize = 320,
    this.candidateConfidence = 0.25,
    this.nmsIouThreshold = 0.7,
    this.trackMatchIou = 0.3,
    this.positionHysteresis = 0.05,
    this.showDebugOverlay = false,
    this.metricsFlushInterval = const Duration(seconds: 5),
    this.deviceSampleInterval = const Duration(seconds: 10),
    this.detectionTimeout = const Duration(seconds: 10),
    this.evaluationMode = false,
  }) : assert(
         targetInferencesPerSecond >= minInferencesPerSecond &&
             targetInferencesPerSecond <= maxInferencesPerSecond,
       ),
       assert(confidenceThreshold > 0 && confidenceThreshold < 1),
       assert(confirmationHits >= 1 && confirmationHits <= confirmationWindow),
       assert(maxObjectsPerSentence >= 1),
       assert(leftRegionEnd > 0 && leftRegionEnd < rightRegionStart),
       assert(rightRegionStart < 1),
       assert(speechVolume >= 0 && speechVolume <= 1);

  /// Lower bound for [targetInferencesPerSecond] (CLAUDE.md: 3–5).
  static const double minInferencesPerSecond = 3;

  /// Upper bound for [targetInferencesPerSecond] (CLAUDE.md: 3–5).
  static const double maxInferencesPerSecond = 5;

  /// How many inferences the FrameScheduler aims to run per second.
  final double targetInferencesPerSecond;

  /// Detections below this confidence are discarded and never spoken.
  final double confidenceThreshold;

  /// N in "confirmed in N of the last M results".
  final int confirmationHits;

  /// M in "confirmed in N of the last M results".
  final int confirmationWindow;

  /// Minimum time before the same object (same position) is repeated.
  final Duration repeatCooldown;

  /// Maximum number of objects announced in one sentence.
  final int maxObjectsPerSentence;

  /// Normalized x (0–1) of a box centre below which it is "left".
  final double leftRegionEnd;

  /// Normalized x (0–1) of a box centre at or above which it is "right".
  final double rightRegionStart;

  /// Speech output volume, 0–1.
  final double speechVolume;

  /// If a speech engine has not started within this time, the utterance is
  /// treated as failed so a silent engine cannot block speech forever.
  final Duration speechStartTimeout;

  /// Camera resolution tier. Frames are downscaled to the model input anyway.
  final CameraQuality cameraQuality;

  /// Square model input in pixels. Must match the bundled model file (D-019).
  final int modelInputSize;

  /// Detections below this are discarded by the detector. Speech applies the
  /// stricter [confidenceThreshold]; this keeps weaker results for evaluation.
  final double candidateConfidence;

  /// Boxes of one class overlapping more than this are merged by NMS.
  final double nmsIouThreshold;

  /// Minimum overlap for a detection to continue an existing track.
  final double trackMatchIou;

  /// How far (normalized x) a box centre must pass a region boundary before its
  /// position changes, so an object near a boundary is not re-announced.
  final double positionHysteresis;

  /// Draws detection boxes over the preview. Debug builds only.
  final bool showDebugOverlay;

  /// How often evaluation rows are written to disk. A crash loses at most this.
  final Duration metricsFlushInterval;

  /// How often RAM, battery and frame rates are sampled during evaluation.
  final Duration deviceSampleInterval;

  /// A detection taking longer than this counts as a hung detector: the worker
  /// is restarted and the user is told, instead of detection stopping silently.
  /// GPU setup happens while loading, not here, so this can be generous.
  final Duration detectionTimeout;

  /// When true, metrics are logged and debug overlays may be shown.
  final bool evaluationMode;

  /// Minimum interval between two inference starts.
  Duration get minInferenceInterval => Duration(
    microseconds: (Duration.microsecondsPerSecond / targetInferencesPerSecond)
        .round(),
  );

  /// Every setting, for each evaluation session's `session.json`. A test checks
  /// that no setting is missing.
  Map<String, Object?> toJson() => <String, Object?>{
    'targetInferencesPerSecond': targetInferencesPerSecond,
    'confidenceThreshold': confidenceThreshold,
    'confirmationHits': confirmationHits,
    'confirmationWindow': confirmationWindow,
    'repeatCooldownMs': repeatCooldown.inMilliseconds,
    'maxObjectsPerSentence': maxObjectsPerSentence,
    'leftRegionEnd': leftRegionEnd,
    'rightRegionStart': rightRegionStart,
    'speechVolume': speechVolume,
    'speechStartTimeoutMs': speechStartTimeout.inMilliseconds,
    'cameraQuality': cameraQuality.name,
    'modelInputSize': modelInputSize,
    'candidateConfidence': candidateConfidence,
    'nmsIouThreshold': nmsIouThreshold,
    'trackMatchIou': trackMatchIou,
    'positionHysteresis': positionHysteresis,
    'showDebugOverlay': showDebugOverlay,
    'metricsFlushIntervalMs': metricsFlushInterval.inMilliseconds,
    'deviceSampleIntervalMs': deviceSampleInterval.inMilliseconds,
    'detectionTimeoutMs': detectionTimeout.inMilliseconds,
    'evaluationMode': evaluationMode,
  };

  AppSettings copyWith({
    double? targetInferencesPerSecond,
    double? confidenceThreshold,
    int? confirmationHits,
    int? confirmationWindow,
    Duration? repeatCooldown,
    int? maxObjectsPerSentence,
    double? leftRegionEnd,
    double? rightRegionStart,
    double? speechVolume,
    Duration? speechStartTimeout,
    CameraQuality? cameraQuality,
    int? modelInputSize,
    double? candidateConfidence,
    double? nmsIouThreshold,
    double? trackMatchIou,
    double? positionHysteresis,
    bool? showDebugOverlay,
    Duration? metricsFlushInterval,
    Duration? deviceSampleInterval,
    Duration? detectionTimeout,
    bool? evaluationMode,
  }) {
    return AppSettings(
      targetInferencesPerSecond:
          targetInferencesPerSecond ?? this.targetInferencesPerSecond,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      confirmationHits: confirmationHits ?? this.confirmationHits,
      confirmationWindow: confirmationWindow ?? this.confirmationWindow,
      repeatCooldown: repeatCooldown ?? this.repeatCooldown,
      maxObjectsPerSentence:
          maxObjectsPerSentence ?? this.maxObjectsPerSentence,
      leftRegionEnd: leftRegionEnd ?? this.leftRegionEnd,
      rightRegionStart: rightRegionStart ?? this.rightRegionStart,
      speechVolume: speechVolume ?? this.speechVolume,
      speechStartTimeout: speechStartTimeout ?? this.speechStartTimeout,
      cameraQuality: cameraQuality ?? this.cameraQuality,
      modelInputSize: modelInputSize ?? this.modelInputSize,
      candidateConfidence: candidateConfidence ?? this.candidateConfidence,
      nmsIouThreshold: nmsIouThreshold ?? this.nmsIouThreshold,
      trackMatchIou: trackMatchIou ?? this.trackMatchIou,
      positionHysteresis: positionHysteresis ?? this.positionHysteresis,
      showDebugOverlay: showDebugOverlay ?? this.showDebugOverlay,
      metricsFlushInterval: metricsFlushInterval ?? this.metricsFlushInterval,
      deviceSampleInterval: deviceSampleInterval ?? this.deviceSampleInterval,
      detectionTimeout: detectionTimeout ?? this.detectionTimeout,
      evaluationMode: evaluationMode ?? this.evaluationMode,
    );
  }
}
