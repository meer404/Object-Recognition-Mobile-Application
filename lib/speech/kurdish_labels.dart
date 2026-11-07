import '../detection/detection_result.dart';

/// Sorani word for one object class.
class KurdishLabel {
  const KurdishLabel({
    required this.modelName,
    required this.word,
    required this.indefinite,
  });

  /// Class name in assets/models/labels.txt, e.g. `dining table`. Not spoken;
  /// a test uses it to catch a label attached to the wrong class id.
  final String modelName;

  /// Bare form, e.g. مێز.
  final String word;

  /// Indefinite form, e.g. مێزێک.
  final String indefinite;
}

/// THE single source of object labels: model class id → Sorani label.
///
/// The model detects all 80 COCO classes; only the classes listed here are in
/// scope for speech (docs/decisions.md D-014).
///
/// Mirrored in docs/kurdish_labels.md for native-speaker review.
/// Every new entry MUST carry a `// REVIEW` comment until it is verified.
const Map<int, KurdishLabel> kurdishLabels = <int, KurdishLabel>{
  // REVIEW
  0: KurdishLabel(modelName: 'person', word: 'کەس', indefinite: 'کەسێک'),
  // REVIEW
  2: KurdishLabel(modelName: 'car', word: 'ئۆتۆمبێل', indefinite: 'ئۆتۆمبێلێک'),
  // REVIEW
  24: KurdishLabel(
    modelName: 'backpack',
    word: 'جانتای پشت',
    indefinite: 'جانتایەکی پشت',
  ),
  // REVIEW
  26: KurdishLabel(modelName: 'handbag', word: 'جانتا', indefinite: 'جانتایەک'),
  // REVIEW
  39: KurdishLabel(modelName: 'bottle', word: 'بوتڵ', indefinite: 'بوتڵێک'),
  // REVIEW
  41: KurdishLabel(modelName: 'cup', word: 'پەرداخ', indefinite: 'پەرداخێک'),
  // REVIEW
  45: KurdishLabel(modelName: 'bowl', word: 'قاپ', indefinite: 'قاپێک'),
  // REVIEW
  56: KurdishLabel(modelName: 'chair', word: 'کورسی', indefinite: 'کورسییەک'),
  // REVIEW
  57: KurdishLabel(modelName: 'couch', word: 'قەنەفە', indefinite: 'قەنەفەیەک'),
  // REVIEW
  59: KurdishLabel(
    modelName: 'bed',
    word: 'قەرەوێڵە',
    indefinite: 'قەرەوێڵەیەک',
  ),
  // REVIEW
  60: KurdishLabel(modelName: 'dining table', word: 'مێز', indefinite: 'مێزێک'),
  // REVIEW
  61: KurdishLabel(
    modelName: 'toilet',
    word: 'تەوالێت',
    indefinite: 'تەوالێتێک',
  ),
  // REVIEW
  62: KurdishLabel(
    modelName: 'tv',
    word: 'تەلەفزیۆن',
    indefinite: 'تەلەفزیۆنێک',
  ),
  // REVIEW
  63: KurdishLabel(modelName: 'laptop', word: 'لاپتۆپ', indefinite: 'لاپتۆپێک'),
  // REVIEW
  65: KurdishLabel(modelName: 'remote', word: 'ڕیمۆت', indefinite: 'ڕیمۆتێک'),
  // REVIEW
  67: KurdishLabel(
    modelName: 'cell phone',
    word: 'مۆبایل',
    indefinite: 'مۆبایلێک',
  ),
  // REVIEW
  71: KurdishLabel(modelName: 'sink', word: 'دەستشۆر', indefinite: 'دەستشۆرێک'),
  // REVIEW
  72: KurdishLabel(
    modelName: 'refrigerator',
    word: 'سەلاجە',
    indefinite: 'سەلاجەیەک',
  ),
  // REVIEW
  73: KurdishLabel(modelName: 'book', word: 'کتێب', indefinite: 'کتێبێک'),
  // REVIEW
  74: KurdishLabel(
    modelName: 'clock',
    word: 'کاتژمێر',
    indefinite: 'کاتژمێرێک',
  ),
};

/// Position phrases (given in CLAUDE.md).
const Map<HorizontalPosition, String> positionPhrases =
    <HorizontalPosition, String>{
      HorizontalPosition.left: 'لای چەپ',
      HorizontalPosition.center: 'لە ناوەڕاست',
      HorizontalPosition.right: 'لای ڕاست',
    };
