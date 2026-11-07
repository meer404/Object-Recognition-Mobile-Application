/// All user-facing UI strings (Sorani). Object labels are NOT here; they live
/// in lib/speech/kurdish_labels.dart.
///
/// Every string marked `// REVIEW` awaits native-speaker verification and is
/// mirrored in docs/kurdish_labels.md.
abstract final class UiStrings {
  // REVIEW
  static const String appTitle = 'بینینی کوردی';

  // REVIEW — "Preparing…"
  static const String preparing = 'ئامادە دەکرێت…';

  // REVIEW — "Object recognition is running."
  static const String running = 'ناسینەوەی شتەکان کار دەکات.';

  // REVIEW — "Object recognition is paused."
  static const String paused = 'ناسینەوەی شتەکان ڕاگیراوە.';

  // REVIEW — "Camera permission was not given. Allow it in your phone's
  // settings, then touch the screen to try again."
  static const String permissionDenied =
      'ڕێگەی بەکارهێنانی کامێرا نەدراوە. لە ڕێکخستنەکانی مۆبایلەکەت ڕێگە بدە، پاشان پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە.';

  // REVIEW — "No camera was found. Touch the screen to try again."
  static const String noCamera =
      'هیچ کامێرایەک نەدۆزرایەوە. پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە.';

  // REVIEW — "A camera error occurred. Touch the screen to try again."
  static const String cameraError =
      'هەڵەیەک لە کامێرادا ڕوویدا. پەنجە لە شاشەکە بدە بۆ هەوڵدانەوە.';

  // REVIEW — "Repeat" (screen-reader action)
  static const String repeatAction = 'دووبارەکردنەوە';

  // REVIEW — "Try again" (screen-reader action)
  static const String retryAction = 'هەوڵدانەوە';

  // REVIEW — "Pause" (screen-reader action)
  static const String pauseAction = 'ڕاگرتن';

  // REVIEW — "Resume" (screen-reader action)
  static const String resumeAction = 'دەستپێکردنەوە';

  // REVIEW — "Settings"
  static const String settings = 'ڕێکخستنەکان';

  // REVIEW — "Back" (replaces the framework's Arabic tooltip, D-004)
  static const String back = 'گەڕانەوە';

  // REVIEW — "Settings will be added in a later version."
  static const String settingsPlaceholder =
      'ڕێکخستنەکان لە وەشانی داهاتوودا زیاد دەکرێن.';

  /// Every string above, so a test can check the review sheet is complete.
  static const List<String> all = <String>[
    appTitle,
    preparing,
    running,
    paused,
    permissionDenied,
    noCamera,
    cameraError,
    repeatAction,
    retryAction,
    pauseAction,
    resumeAction,
    settings,
    back,
    settingsPlaceholder,
  ];
}
