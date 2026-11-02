import '../detection/detection_result.dart';

/// Sorani word for one object class.
class KurdishLabel {
  const KurdishLabel({required this.word, required this.indefinite});

  /// Bare form, e.g. مێز.
  final String word;

  /// Indefinite form, e.g. مێزێک.
  final String indefinite;
}

/// THE single source of object labels: model class id → Sorani label.
///
/// Mirrored in docs/kurdish_labels.md for native-speaker review.
/// Every new entry MUST carry a `// REVIEW` comment until it is verified.
/// Filled in Phase 1C.
const Map<int, KurdishLabel> kurdishLabels = <int, KurdishLabel>{};

/// Position phrases (given in CLAUDE.md).
const Map<HorizontalPosition, String> positionPhrases =
    <HorizontalPosition, String>{
      HorizontalPosition.left: 'لای چەپ',
      HorizontalPosition.center: 'لە ناوەڕاست',
      HorizontalPosition.right: 'لای ڕاست',
    };
