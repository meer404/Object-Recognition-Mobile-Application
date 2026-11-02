/// Central, immutable configuration for the whole pipeline.
///
/// Every threshold used anywhere in the app lives here so that no stage
/// contains magic numbers and every experiment in the evaluation can state
/// exactly which configuration it ran with. Defaults follow CLAUDE.md.
library;

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

  /// When true, metrics are logged and debug overlays may be shown.
  final bool evaluationMode;

  /// Minimum interval between two inference starts.
  Duration get minInferenceInterval => Duration(
    microseconds: (Duration.microsecondsPerSecond / targetInferencesPerSecond)
        .round(),
  );

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
      evaluationMode: evaluationMode ?? this.evaluationMode,
    );
  }
}
