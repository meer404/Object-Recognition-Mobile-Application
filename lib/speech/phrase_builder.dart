import '../detection/detection_result.dart';
import '../settings/app_settings.dart';
import 'kurdish_labels.dart';
import 'speech_service.dart';

/// A sentence and which classes it mentions.
class Phrase {
  const Phrase({required this.request, required this.classes});

  final SpeechRequest request;
  final Set<int> classes;
}

/// Builds Sorani sentences from objects to announce, for example
/// «لەبەردەمت مێزێک هەیە. پەرداخێک و کورسییەکیش دەبینرێن.»
///
/// At most [AppSettings.maxObjectsPerSentence] objects, largest and most
/// confident first (D-020). Only the main object gets a position, to keep
/// sentences short. Each class is named once, and a class without a label is
/// never spoken.
///
/// «ـیش» is a whole recorded word (`class_<id>_also`) rather than a suffix clip,
/// so joined clips do not sound choppy.
class PhraseBuilder {
  PhraseBuilder({required this.settings});

  AppSettings settings;

  /// Returns the sentence for [objects], or null if there is nothing to say.
  Phrase? build(Iterable<DetectionResult> objects, {bool interrupt = false}) {
    final List<DetectionResult> ranked = <DetectionResult>[
      for (final DetectionResult d in objects)
        if (kurdishLabels.containsKey(d.classId)) d,
    ]..sort(_byPriority);

    final List<DetectionResult> chosen = <DetectionResult>[];
    final Set<int> classes = <int>{};
    for (final DetectionResult d in ranked) {
      if (chosen.length == settings.maxObjectsPerSentence) break;
      if (classes.add(d.classId)) chosen.add(d);
    }
    if (chosen.isEmpty) return null;

    final DetectionResult main = chosen.first;
    final String opener = switch (main.position) {
      HorizontalPosition.left => positionPhrases[HorizontalPosition.left]!,
      HorizontalPosition.center => phraseFragments['in_front']!,
      HorizontalPosition.right => positionPhrases[HorizontalPosition.right]!,
    };
    final String openerClip = switch (main.position) {
      HorizontalPosition.left => 'on_left',
      HorizontalPosition.center => 'in_front',
      HorizontalPosition.right => 'on_right',
    };
    final StringBuffer text = StringBuffer(
      '$opener ${kurdishLabels[main.classId]!.indefinite} '
      '${phraseFragments['exists']!}.',
    );
    final List<String> clips = <String>[
      openerClip,
      clipKeyForClass(main.classId),
      'exists',
    ];

    final List<DetectionResult> others = chosen.sublist(1);
    if (others.isNotEmpty) {
      // Every other object but the last is joined with «و»; the last has «ـیش».
      for (final DetectionResult d in others.take(others.length - 1)) {
        text
          ..write(' ${kurdishLabels[d.classId]!.indefinite}')
          ..write(' ${phraseFragments['and']!}');
        clips
          ..add(clipKeyForClass(d.classId))
          ..add('and');
      }
      final int last = others.last.classId;
      final String verb = others.length == 1 ? 'seen_one' : 'seen_many';
      text.write(
        ' ${kurdishLabels[last]!.indefiniteAlso} ${phraseFragments[verb]!}.',
      );
      clips
        ..add(clipKeyForClassAlso(last))
        ..add(verb);
    }

    return Phrase(
      request: SpeechRequest(
        text: text.toString(),
        clipKeys: clips,
        interrupt: interrupt,
      ),
      classes: classes,
    );
  }

  /// What Repeat says when nothing is confirmed.
  SpeechRequest nothingDetected({bool interrupt = true}) => SpeechRequest(
    text: '${phraseFragments['nothing_detected']!}.',
    clipKeys: const <String>['nothing_detected'],
    interrupt: interrupt,
  );

  /// Confidence × box size, then class id so ties have a fixed order.
  static int _byPriority(DetectionResult a, DetectionResult b) {
    final int byPriority = b.priority.compareTo(a.priority);
    return byPriority != 0 ? byPriority : a.classId.compareTo(b.classId);
  }
}
