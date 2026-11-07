import '../detection/detection_result.dart';

/// Sorani word for one object class.
class KurdishLabel {
  const KurdishLabel({
    required this.modelName,
    required this.word,
    required this.indefinite,
    required this.indefiniteAlso,
  });

  /// Class name in assets/models/labels.txt, e.g. `dining table`. Not spoken;
  /// a test uses it to catch a label attached to the wrong class id.
  final String modelName;

  /// Bare form, e.g. مێز.
  final String word;

  /// Indefinite form, e.g. مێزێک.
  final String indefinite;

  /// Indefinite form with «ـیش» ("also"), e.g. مێزێکیش. A whole word, not a
  /// suffix, so recorded clips join naturally.
  final String indefiniteAlso;
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
  0: KurdishLabel(
    modelName: 'person',
    word: 'کەس',
    indefinite: 'کەسێک',
    indefiniteAlso: 'کەسێکیش',
  ),
  // REVIEW
  2: KurdishLabel(
    modelName: 'car',
    word: 'ئۆتۆمبێل',
    indefinite: 'ئۆتۆمبێلێک',
    indefiniteAlso: 'ئۆتۆمبێلێکیش',
  ),
  // REVIEW
  24: KurdishLabel(
    modelName: 'backpack',
    word: 'جانتای پشت',
    indefinite: 'جانتایەکی پشت',
    indefiniteAlso: 'جانتایەکی پشتیش',
  ),
  // REVIEW
  26: KurdishLabel(
    modelName: 'handbag',
    word: 'جانتا',
    indefinite: 'جانتایەک',
    indefiniteAlso: 'جانتایەکیش',
  ),
  // REVIEW
  39: KurdishLabel(
    modelName: 'bottle',
    word: 'بوتڵ',
    indefinite: 'بوتڵێک',
    indefiniteAlso: 'بوتڵێکیش',
  ),
  // REVIEW
  41: KurdishLabel(
    modelName: 'cup',
    word: 'پەرداخ',
    indefinite: 'پەرداخێک',
    indefiniteAlso: 'پەرداخێکیش',
  ),
  // REVIEW
  45: KurdishLabel(
    modelName: 'bowl',
    word: 'قاپ',
    indefinite: 'قاپێک',
    indefiniteAlso: 'قاپێکیش',
  ),
  // REVIEW
  56: KurdishLabel(
    modelName: 'chair',
    word: 'کورسی',
    indefinite: 'کورسییەک',
    indefiniteAlso: 'کورسییەکیش',
  ),
  // REVIEW
  57: KurdishLabel(
    modelName: 'couch',
    word: 'قەنەفە',
    indefinite: 'قەنەفەیەک',
    indefiniteAlso: 'قەنەفەیەکیش',
  ),
  // REVIEW
  59: KurdishLabel(
    modelName: 'bed',
    word: 'قەرەوێڵە',
    indefinite: 'قەرەوێڵەیەک',
    indefiniteAlso: 'قەرەوێڵەیەکیش',
  ),
  // REVIEW
  60: KurdishLabel(
    modelName: 'dining table',
    word: 'مێز',
    indefinite: 'مێزێک',
    indefiniteAlso: 'مێزێکیش',
  ),
  // REVIEW
  61: KurdishLabel(
    modelName: 'toilet',
    word: 'تەوالێت',
    indefinite: 'تەوالێتێک',
    indefiniteAlso: 'تەوالێتێکیش',
  ),
  // REVIEW
  62: KurdishLabel(
    modelName: 'tv',
    word: 'تەلەفزیۆن',
    indefinite: 'تەلەفزیۆنێک',
    indefiniteAlso: 'تەلەفزیۆنێکیش',
  ),
  // REVIEW
  63: KurdishLabel(
    modelName: 'laptop',
    word: 'لاپتۆپ',
    indefinite: 'لاپتۆپێک',
    indefiniteAlso: 'لاپتۆپێکیش',
  ),
  // REVIEW
  65: KurdishLabel(
    modelName: 'remote',
    word: 'ڕیمۆت',
    indefinite: 'ڕیمۆتێک',
    indefiniteAlso: 'ڕیمۆتێکیش',
  ),
  // REVIEW
  67: KurdishLabel(
    modelName: 'cell phone',
    word: 'مۆبایل',
    indefinite: 'مۆبایلێک',
    indefiniteAlso: 'مۆبایلێکیش',
  ),
  // REVIEW
  71: KurdishLabel(
    modelName: 'sink',
    word: 'دەستشۆر',
    indefinite: 'دەستشۆرێک',
    indefiniteAlso: 'دەستشۆرێکیش',
  ),
  // REVIEW
  72: KurdishLabel(
    modelName: 'refrigerator',
    word: 'سەلاجە',
    indefinite: 'سەلاجەیەک',
    indefiniteAlso: 'سەلاجەیەکیش',
  ),
  // REVIEW
  73: KurdishLabel(
    modelName: 'book',
    word: 'کتێب',
    indefinite: 'کتێبێک',
    indefiniteAlso: 'کتێبێکیش',
  ),
  // REVIEW
  74: KurdishLabel(
    modelName: 'clock',
    word: 'کاتژمێر',
    indefinite: 'کاتژمێرێک',
    indefiniteAlso: 'کاتژمێرێکیش',
  ),
};

/// Sentence pieces other than object names, keyed by their clip name. Draft
/// wording: reviewed with everything else in docs/kurdish_labels.md.
// REVIEW
const Map<String, String> phraseFragments = <String, String>{
  'in_front': 'لەبەردەمت',
  'exists': 'هەیە',
  'and': 'و',
  'seen_one': 'دەبینرێت',
  'seen_many': 'دەبینرێن',
  'nothing_detected': 'هیچ شتێک نەناسرایەوە',
};

/// Clip key of a class's indefinite form.
String clipKeyForClass(int classId) => 'class_$classId';

/// Clip key of a class's «ـیش» form.
String clipKeyForClassAlso(int classId) => 'class_${classId}_also';

/// Every clip the app can speak: clip key → Sorani text. The recording list.
Map<String, String> allClipTexts() => <String, String>{
  for (final MapEntry<int, KurdishLabel> e in kurdishLabels.entries) ...{
    clipKeyForClass(e.key): e.value.indefinite,
    clipKeyForClassAlso(e.key): e.value.indefiniteAlso,
  },
  ...phraseFragments,
  'on_left': positionPhrases[HorizontalPosition.left]!,
  'on_right': positionPhrases[HorizontalPosition.right]!,
};

/// Position phrases (given in CLAUDE.md).
const Map<HorizontalPosition, String> positionPhrases =
    <HorizontalPosition, String>{
      HorizontalPosition.left: 'لای چەپ',
      HorizontalPosition.center: 'لە ناوەڕاست',
      HorizontalPosition.right: 'لای ڕاست',
    };
