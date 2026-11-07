import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/detection/detection_result.dart';
import 'package:kurdish_vision/detection/postprocessing.dart';
import 'package:kurdish_vision/detection/preprocessing.dart';
import 'package:kurdish_vision/settings/app_settings.dart';

const int _classes = 3;
const int _channels = 4 + _classes;
const AppSettings _settings = AppSettings();

/// Builds a raw tensor from `[cx, cy, w, h, classId, score]` anchors.
Float32List _raw(List<List<double>> anchors) {
  final int n = anchors.length;
  final Float32List raw = Float32List(_channels * n);
  for (int a = 0; a < n; a++) {
    for (int c = 0; c < 4; c++) {
      raw[c * n + a] = anchors[a][c];
    }
    raw[(4 + anchors[a][4].toInt()) * n + a] = anchors[a][5];
  }
  return raw;
}

// A square input that maps straight onto a square image.
final LetterboxGeometry _square = LetterboxGeometry.forImage(
  width: 100,
  height: 100,
  inputSize: 100,
);

List<DetectionResult> _decode(
  List<List<double>> anchors, {
  Set<int> allowed = const <int>{0, 1, 2},
  LetterboxGeometry? geometry,
}) => decodeDetections(
  _raw(anchors),
  channels: _channels,
  anchors: anchors.length,
  geometry: geometry ?? _square,
  settings: _settings,
  allowedClasses: allowed,
);

void main() {
  test('decodes centre xywh to a normalized box', () {
    final DetectionResult d = _decode(<List<double>>[
      <double>[0.5, 0.5, 0.2, 0.4, 1, 0.9],
    ]).single;
    expect(d.classId, 1);
    expect(d.confidence, closeTo(0.9, 1e-6));
    expect(d.box.left, closeTo(0.4, 1e-6));
    expect(d.box.top, closeTo(0.3, 1e-6));
    expect(d.box.right, closeTo(0.6, 1e-6));
    expect(d.box.bottom, closeTo(0.7, 1e-6));
    expect(d.position, HorizontalPosition.center);
  });

  test('takes the highest-scoring class of an anchor', () {
    final Float32List raw = _raw(<List<double>>[
      <double>[0.5, 0.5, 0.2, 0.2, 0, 0.4],
    ]);
    raw[6] = 0.8; // Class 2 of the only anchor.
    final List<DetectionResult> result = decodeDetections(
      raw,
      channels: _channels,
      anchors: 1,
      geometry: _square,
      settings: _settings,
      allowedClasses: const <int>{0, 1, 2},
    );
    expect(result.single.classId, 2);
  });

  test('drops scores below the candidate floor, keeps those at it', () {
    final double floor = _settings.candidateConfidence;
    expect(
      _decode(<List<double>>[
        <double>[0.2, 0.5, 0.1, 0.1, 0, floor - 0.01],
        <double>[0.8, 0.5, 0.1, 0.1, 0, floor],
      ]),
      hasLength(1),
    );
  });

  test('keeps only allowed classes', () {
    final List<DetectionResult> result = _decode(
      <List<double>>[
        <double>[0.2, 0.5, 0.1, 0.1, 0, 0.9],
        <double>[0.8, 0.5, 0.1, 0.1, 1, 0.9],
      ],
      allowed: const <int>{1},
    );
    expect(result.single.classId, 1);
  });

  test('assigns left, center and right from the box centre', () {
    final List<DetectionResult> result = _decode(<List<double>>[
      <double>[0.1, 0.5, 0.1, 0.1, 0, 0.9],
      <double>[0.5, 0.5, 0.1, 0.1, 1, 0.8],
      <double>[0.9, 0.5, 0.1, 0.1, 2, 0.7],
    ]);
    expect(result.map((DetectionResult d) => d.position), <HorizontalPosition>[
      HorizontalPosition.left,
      HorizontalPosition.center,
      HorizontalPosition.right,
    ]);
  });

  group('NMS', () {
    test('removes an overlapping box of the same class, keeps the best', () {
      final List<DetectionResult> result = _decode(<List<double>>[
        <double>[0.5, 0.5, 0.4, 0.4, 0, 0.6],
        <double>[0.51, 0.5, 0.4, 0.4, 0, 0.9],
      ]);
      expect(result.single.confidence, closeTo(0.9, 1e-6));
    });

    test('keeps overlapping boxes of different classes', () {
      expect(
        _decode(<List<double>>[
          <double>[0.5, 0.5, 0.4, 0.4, 0, 0.9],
          <double>[0.5, 0.5, 0.4, 0.4, 1, 0.8],
        ]),
        hasLength(2),
      );
    });

    test('keeps separate boxes of the same class', () {
      expect(
        _decode(<List<double>>[
          <double>[0.2, 0.5, 0.2, 0.2, 0, 0.9],
          <double>[0.8, 0.5, 0.2, 0.2, 0, 0.8],
        ]),
        hasLength(2),
      );
    });

    test('an overlap exactly at the threshold is kept', () {
      // Same top and height. The second box's width is 0.7, so IoU = 0.7.
      final List<DetectionResult> result = _decode(<List<double>>[
        <double>[0.5, 0.5, 0.5, 0.5, 0, 0.9],
        <double>[0.425, 0.5, 0.35, 0.5, 0, 0.8],
      ]);
      expect(result, hasLength(2));
    });

    test('results are sorted by confidence', () {
      final List<DetectionResult> result = _decode(<List<double>>[
        <double>[0.2, 0.5, 0.1, 0.1, 0, 0.5],
        <double>[0.5, 0.5, 0.1, 0.1, 1, 0.9],
        <double>[0.8, 0.5, 0.1, 0.1, 2, 0.7],
      ]);
      expect(result.map((DetectionResult d) => d.classId), <int>[1, 2, 0]);
    });
  });

  test('zero-size boxes and empty output do not crash', () {
    expect(
      _decode(<List<double>>[
        <double>[0.5, 0.5, 0, 0, 0, 0.9],
        <double>[0.5, 0.5, 0, 0, 0, 0.8],
      ]),
      hasLength(2),
    );
    expect(_decode(<List<double>>[]), isEmpty);
  });

  test('a tensor of the wrong size is rejected', () {
    expect(
      () => decodeDetections(
        Float32List(5),
        channels: _channels,
        anchors: 1,
        geometry: _square,
        settings: _settings,
        allowedClasses: const <int>{0},
      ),
      throwsArgumentError,
    );
  });

  test('matches an independent decode of real model output', () {
    final Map<String, dynamic> fixture =
        jsonDecode(
              File('test/fixtures/detector_bus_320.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final int channels = fixture['channels'] as int;
    final int anchors = fixture['anchors'] as int;
    final Float32List raw = Float32List(channels * anchors);
    for (final dynamic item in fixture['sparse_output'] as List<dynamic>) {
      final Map<String, dynamic> entry = item as Map<String, dynamic>;
      final int a = entry['anchor'] as int;
      final List<dynamic> box = entry['box'] as List<dynamic>;
      for (int c = 0; c < 4; c++) {
        raw[c * anchors + a] = (box[c] as num).toDouble();
      }
      (entry['scores'] as Map<String, dynamic>).forEach((
        String cls,
        dynamic v,
      ) {
        raw[(4 + int.parse(cls)) * anchors + a] = (v as num).toDouble();
      });
    }
    final List<DetectionResult> result = decodeDetections(
      raw,
      channels: channels,
      anchors: anchors,
      geometry: LetterboxGeometry.forImage(
        width: fixture['image_width'] as int,
        height: fixture['image_height'] as int,
        inputSize: fixture['size'] as int,
      ),
      settings: AppSettings(
        candidateConfidence: (fixture['conf'] as num).toDouble(),
        nmsIouThreshold: (fixture['nms_iou'] as num).toDouble(),
      ),
      allowedClasses: <int>{for (int c = 0; c < channels - 4; c++) c},
    );

    final List<dynamic> expected = fixture['expected'] as List<dynamic>;
    expect(expected, isNotEmpty);
    expect(result, hasLength(expected.length));
    for (int i = 0; i < expected.length; i++) {
      final Map<String, dynamic> e = expected[i] as Map<String, dynamic>;
      final List<dynamic> box = e['box'] as List<dynamic>;
      expect(result[i].classId, e['class'], reason: 'detection $i');
      expect(result[i].confidence, closeTo(e['confidence'] as num, 1e-5));
      expect(result[i].box.left, closeTo(box[0] as num, 1e-4));
      expect(result[i].box.top, closeTo(box[1] as num, 1e-4));
      expect(result[i].box.right, closeTo(box[2] as num, 1e-4));
      expect(result[i].box.bottom, closeTo(box[3] as num, 1e-4));
    }
  });
}
