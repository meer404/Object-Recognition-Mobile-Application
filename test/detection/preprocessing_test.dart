import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/detection/preprocessing.dart';

CameraFrame _bgra(
  int width,
  int height,
  List<List<int>> rgbPixels, {
  int rotation = 0,
}) {
  final Uint8List bytes = Uint8List(width * height * 4);
  for (int i = 0; i < rgbPixels.length; i++) {
    bytes[i * 4] = rgbPixels[i][2];
    bytes[i * 4 + 1] = rgbPixels[i][1];
    bytes[i * 4 + 2] = rgbPixels[i][0];
    bytes[i * 4 + 3] = 255;
  }
  return CameraFrame(
    width: width,
    height: height,
    format: FrameFormat.bgra8888,
    planes: <FramePlane>[FramePlane(bytes: bytes, bytesPerRow: width * 4)],
    timestamp: DateTime.utc(2026),
    rotationDegrees: rotation,
  );
}

/// Pixel of the tensor as 0–255 RGB.
List<int> _pixel(Float32List tensor, int size, int x, int y) => <int>[
  for (int c = 0; c < 3; c++)
    (tensor[c * size * size + y * size + x] * 255).round(),
];

Float32List _run(CameraFrame frame, int size) => preprocessFrame(
  frame,
  LetterboxGeometry.forImage(
    width: uprightWidth(frame),
    height: uprightHeight(frame),
    inputSize: size,
  ),
);

const List<int> _red = <int>[200, 10, 10];
const List<int> _green = <int>[10, 200, 10];
const List<int> _blue = <int>[10, 10, 200];
const List<int> _white = <int>[250, 250, 250];

void main() {
  group('LetterboxGeometry', () {
    test('portrait image gets side padding', () {
      final LetterboxGeometry g = LetterboxGeometry.forImage(
        width: 810,
        height: 1080,
        inputSize: 320,
      );
      expect(g.newWidth, 240);
      expect(g.newHeight, 320);
      expect(g.left, 40);
      expect(g.top, 0);
    });

    test('landscape image gets top padding', () {
      final LetterboxGeometry g = LetterboxGeometry.forImage(
        width: 640,
        height: 480,
        inputSize: 320,
      );
      expect(g.newHeight, 240);
      expect(g.top, 40);
      expect(g.left, 0);
    });

    test('boxes map back to the upright image', () {
      final LetterboxGeometry g = LetterboxGeometry.forImage(
        width: 810,
        height: 1080,
        inputSize: 320,
      );
      // The input's content spans x from 40/320 to 280/320.
      final box = g.toUprightBox(40 / 320, 0, 280 / 320, 0.5);
      expect(box.left, closeTo(0, 1e-9));
      expect(box.right, closeTo(1, 1e-9));
      expect(box.bottom, closeTo(0.5, 1e-9));
    });

    test('boxes reaching into the padding are clamped', () {
      final LetterboxGeometry g = LetterboxGeometry.forImage(
        width: 810,
        height: 1080,
        inputSize: 320,
      );
      final box = g.toUprightBox(0, -0.1, 1, 1.1);
      expect(box.left, 0);
      expect(box.top, 0);
      expect(box.right, 1);
      expect(box.bottom, 1);
    });
  });

  group('tensor layout', () {
    test('fills padding with grey and content with the image', () {
      final CameraFrame frame = _bgra(2, 4, List<List<int>>.filled(8, _red));
      final Float32List tensor = _run(frame, 8);
      expect(tensor, hasLength(3 * 64));
      expect(_pixel(tensor, 8, 0, 0), <int>[114, 114, 114], reason: 'padding');
      expect(_pixel(tensor, 8, 7, 7), <int>[114, 114, 114], reason: 'padding');
      expect(_pixel(tensor, 8, 4, 4), _red, reason: 'content');
    });

    test('values are scaled to 0–1 and channels are planar RGB', () {
      final Float32List tensor = _run(
        _bgra(1, 1, <List<int>>[
          <int>[255, 0, 51],
        ]),
        1,
      );
      expect(tensor[0], closeTo(1.0, 1e-6));
      expect(tensor[1], closeTo(0.0, 1e-6));
      expect(tensor[2], closeTo(0.2, 1e-6));
    });

    test('reuses the output buffer when it fits', () {
      final Float32List buffer = Float32List(3);
      final CameraFrame frame = _bgra(1, 1, <List<int>>[_red]);
      final Float32List tensor = preprocessFrame(
        frame,
        LetterboxGeometry.forImage(width: 1, height: 1, inputSize: 1),
        output: buffer,
      );
      expect(identical(tensor, buffer), isTrue);
    });
  });

  group('rotation', () {
    // Sensor image:  red   green
    //                blue  white
    final List<List<int>> corners = <List<int>>[_red, _green, _blue, _white];

    Map<String, List<int>> cornersAfter(int rotation) {
      final Float32List t = _run(_bgra(2, 2, corners, rotation: rotation), 2);
      return <String, List<int>>{
        'topLeft': _pixel(t, 2, 0, 0),
        'topRight': _pixel(t, 2, 1, 0),
        'bottomLeft': _pixel(t, 2, 0, 1),
        'bottomRight': _pixel(t, 2, 1, 1),
      };
    }

    test('0 degrees leaves it unchanged', () {
      expect(cornersAfter(0), <String, List<int>>{
        'topLeft': _red,
        'topRight': _green,
        'bottomLeft': _blue,
        'bottomRight': _white,
      });
    });

    test('90 degrees turns it clockwise', () {
      expect(cornersAfter(90), <String, List<int>>{
        'topLeft': _blue,
        'topRight': _red,
        'bottomLeft': _white,
        'bottomRight': _green,
      });
    });

    test('180 degrees turns it upside down', () {
      expect(cornersAfter(180), <String, List<int>>{
        'topLeft': _white,
        'topRight': _blue,
        'bottomLeft': _green,
        'bottomRight': _red,
      });
    });

    test('270 degrees turns it counter-clockwise', () {
      expect(cornersAfter(270), <String, List<int>>{
        'topLeft': _green,
        'topRight': _white,
        'bottomLeft': _red,
        'bottomRight': _blue,
      });
    });

    test('rotation swaps the upright dimensions', () {
      final CameraFrame frame = _bgra(
        4,
        2,
        List<List<int>>.filled(8, _red),
        rotation: 90,
      );
      expect(uprightWidth(frame), 2);
      expect(uprightHeight(frame), 4);
    });

    test('a non-square rotated frame keeps left and right correct', () {
      // Sensor 2 wide × 1 tall: red, blue. Turned clockwise, red is on top.
      final CameraFrame frame = _bgra(2, 1, <List<int>>[
        _red,
        _blue,
      ], rotation: 90);
      final Float32List t = _run(frame, 2);
      // Upright it is 1 wide × 2 tall, so padding puts the content at x = 0.
      expect(_pixel(t, 2, 0, 0), _red);
      expect(_pixel(t, 2, 0, 1), _blue);
    });
  });

  group('YUV420', () {
    CameraFrame yuv({
      required int y,
      required int u,
      required int v,
      required int pixelStride,
      int rowPadding = 0,
    }) {
      const int width = 4;
      const int height = 4;
      final int yStride = width + rowPadding;
      final int uvStride = width ~/ 2 * pixelStride + rowPadding;
      return CameraFrame(
        width: width,
        height: height,
        format: FrameFormat.yuv420,
        planes: <FramePlane>[
          FramePlane(
            bytes: Uint8List(yStride * height)
              ..fillRange(0, yStride * height, y),
            bytesPerRow: yStride,
            bytesPerPixel: 1,
          ),
          FramePlane(
            bytes: Uint8List(uvStride * 2)..fillRange(0, uvStride * 2, u),
            bytesPerRow: uvStride,
            bytesPerPixel: pixelStride,
          ),
          FramePlane(
            bytes: Uint8List(uvStride * 2)..fillRange(0, uvStride * 2, v),
            bytesPerRow: uvStride,
            bytesPerPixel: pixelStride,
          ),
        ],
        timestamp: DateTime.utc(2026),
      );
    }

    void expectColor(CameraFrame frame, List<int> expected) {
      final List<int> actual = _pixel(_run(frame, 4), 4, 2, 2);
      for (int c = 0; c < 3; c++) {
        expect(actual[c], closeTo(expected[c], 2), reason: 'channel $c');
      }
    }

    test('neutral chroma is grey', () {
      expectColor(yuv(y: 128, u: 128, v: 128, pixelStride: 1), <int>[
        128,
        128,
        128,
      ]);
    });

    test('pure red, green and blue convert correctly (BT.601)', () {
      expectColor(yuv(y: 76, u: 85, v: 255, pixelStride: 1), <int>[254, 0, 0]);
      expectColor(yuv(y: 150, u: 44, v: 21, pixelStride: 1), <int>[0, 255, 1]);
      expectColor(yuv(y: 29, u: 255, v: 107, pixelStride: 1), <int>[0, 0, 255]);
    });

    test('values are clamped rather than wrapping', () {
      expectColor(yuv(y: 255, u: 128, v: 255, pixelStride: 1), <int>[
        255,
        164,
        255,
      ]);
    });

    test('handles interleaved chroma and row padding', () {
      expectColor(
        yuv(y: 76, u: 85, v: 255, pixelStride: 2, rowPadding: 8),
        <int>[254, 0, 0],
      );
    });

    test('reads chroma at half resolution', () {
      // Right half of the chroma plane is red-tinted, left half is neutral.
      const int w = 4;
      final CameraFrame frame = CameraFrame(
        width: w,
        height: 2,
        format: FrameFormat.yuv420,
        planes: <FramePlane>[
          FramePlane(
            bytes: Uint8List(8)..fillRange(0, 8, 128),
            bytesPerRow: w,
            bytesPerPixel: 1,
          ),
          FramePlane(
            bytes: Uint8List.fromList(<int>[128, 128]),
            bytesPerRow: 2,
            bytesPerPixel: 1,
          ),
          FramePlane(
            bytes: Uint8List.fromList(<int>[128, 228]),
            bytesPerRow: 2,
            bytesPerPixel: 1,
          ),
        ],
        timestamp: DateTime.utc(2026),
      );
      final Float32List t = _run(frame, 4);
      expect(_pixel(t, 4, 0, 1)[0], 128, reason: 'left is neutral');
      expect(_pixel(t, 4, 3, 1)[0], greaterThan(200), reason: 'right is red');
    });
  });

  group('matches cv2 / Ultralytics', () {
    final Map<String, dynamic> fixture =
        jsonDecode(
              File(
                'test/fixtures/preprocess_64x48_to_32.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final int width = fixture['width'] as int;
    final int height = fixture['height'] as int;
    final int size = fixture['size'] as int;
    final List<int> rgb = (fixture['rgb'] as List<dynamic>).cast<int>();
    final List<int> expected = (fixture['tensor_uint8_rgb'] as List<dynamic>)
        .cast<int>();

    test('same letterbox geometry', () {
      final LetterboxGeometry g = LetterboxGeometry.forImage(
        width: width,
        height: height,
        inputSize: size,
      );
      expect(g.newWidth, fixture['new_width']);
      expect(g.newHeight, fixture['new_height']);
      expect(g.left, fixture['left']);
      expect(g.top, fixture['top']);
    });

    test('resized pixels are within 2/255 of cv2.INTER_LINEAR', () {
      final CameraFrame frame = _bgra(width, height, <List<int>>[
        for (int i = 0; i < width * height; i++)
          <int>[rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]],
      ]);
      final Float32List tensor = _run(frame, size);
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final List<int> pixel = _pixel(tensor, size, x, y);
          for (int c = 0; c < 3; c++) {
            expect(
              pixel[c],
              closeTo(expected[(y * size + x) * 3 + c], 2),
              reason: 'x $x, y $y, channel $c',
            );
          }
        }
      }
    });
  });
}
