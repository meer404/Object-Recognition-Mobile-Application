/// Runs the app's own detector over a list of photos and writes
/// predictions.json for tools/evaluate.py (D-023).
///
/// It uses the test harness because the real model and native runtime run
/// there on a laptop. It lives outside test/, so plain `flutter test` skips it.
///
///     flutter test tool/eval/predict_test.dart \
///       --dart-define=EVAL_LIST=<dataset>/splits/test.txt \
///       --dart-define=EVAL_OUT=<dataset>/predictions.json \
///       --dart-define=GIT_COMMIT=$(git rev-parse HEAD)
///
/// Optional: EVAL_ROOT (default: the folder above the list's folder, i.e. the
/// dataset root for split_dataset.py output), EVAL_MODEL (default: the app's
/// model), EVAL_MAX_SIDE (default 720, like a medium camera preset).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kurdish_vision/detection/object_detector.dart';
import 'package:kurdish_vision/detection/yolo_detector.dart';
import 'package:kurdish_vision/settings/app_settings.dart';
import 'package:kurdish_vision/speech/kurdish_labels.dart';

import 'image_frames.dart';

const String _list = String.fromEnvironment('EVAL_LIST');
const String _out = String.fromEnvironment('EVAL_OUT');
const String _rootDefine = String.fromEnvironment('EVAL_ROOT');
const String _model = String.fromEnvironment(
  'EVAL_MODEL',
  defaultValue: 'assets/models/yolo26n_320_fp32.tflite',
);
const int _maxSide = int.fromEnvironment('EVAL_MAX_SIDE', defaultValue: 720);
const String _commit = String.fromEnvironment(
  'GIT_COMMIT',
  defaultValue: 'unknown',
);

/// Low enough to keep the whole precision-recall curve for AP. The app's
/// speaking threshold is applied in evaluate.py.
const double _candidateFloor = 0.001;

void main() {
  test(
    'predict',
    skip: _list.isEmpty || _out.isEmpty
        ? 'pass --dart-define=EVAL_LIST=... and EVAL_OUT=... (see this file)'
        : false,
    timeout: Timeout.none,
    () async {
      final File list = File(_list);
      final Directory root = _rootDefine.isNotEmpty
          ? Directory(_rootDefine)
          : list.absolute.parent.parent;
      final File model = File(_model);
      final List<int> modelBytes = model.readAsBytesSync();
      final AppSettings settings = const AppSettings().copyWith(
        candidateConfidence: _candidateFloor,
      );
      final YoloDetector detector = YoloDetector(
        settings: settings,
        allowedClasses: kurdishLabels.keys.toSet(),
        loadModelBytes: model.readAsBytes,
      );
      await detector.load();

      final List<String> files = list
          .readAsLinesSync()
          .map((String l) => l.trim())
          .where((String l) => l.isNotEmpty)
          .toList();
      final List<Map<String, Object?>> images = <Map<String, Object?>>[];
      final List<String> unreadable = <String>[];
      for (int i = 0; i < files.length; i++) {
        final File photo = File('${root.path}/${files[i]}');
        final img.Image upright;
        try {
          upright = loadUpright(photo.readAsBytesSync());
        } on Object catch (e) {
          unreadable.add('${files[i]}: $e');
          continue;
        }
        final DetectionOutput output = await detector.detect(
          frameFromImage(toCameraSize(upright, _maxSide), DateTime.now()),
        );
        images.add(
          imageRecord(
            file: files[i],
            width: upright.width,
            height: upright.height,
            inferenceMs: output.timings.inferenceMs,
            detections: output.detections,
          ),
        );
        if ((i + 1) % 50 == 0) stdout.writeln('${i + 1}/${files.length}');
      }
      final String accelerator = detector.accelerator ?? 'unknown';
      await detector.dispose();

      final Map<String, Object?> result = <String, Object?>{
        'tool': 'tool/eval/predict_test.dart',
        'created_utc': DateTime.now().toUtc().toIso8601String(),
        'git_commit': _commit,
        'model': <String, Object?>{
          'file': _model,
          'bytes': modelBytes.length,
          'sha256': sha256.convert(modelBytes).toString(),
        },
        'accelerator': accelerator,
        'max_side': _maxSide,
        'candidate_confidence': _candidateFloor,
        'settings': settings.toJson(),
        'classes': kurdishLabels.keys.toList()..sort(),
        'list': _list,
        'root': root.path,
        'unreadable': unreadable,
        'images': images,
      };
      File(_out)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '${const JsonEncoder.withIndent(' ').convert(result)}\n',
        );
      stdout.writeln(
        'wrote $_out: ${images.length} images, ${unreadable.length} unreadable, '
        'accelerator $accelerator',
      );
      expect(images, isNotEmpty, reason: 'no image could be read');
    },
  );
}
