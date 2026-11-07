import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/detection/detection_result.dart';

import '../../tool/eval/image_frames.dart';

void main() {
  test('a decoded photo becomes an upright BGRA frame', () {
    final img.Image source = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 200, 10, 30)
      ..setPixelRgb(1, 0, 5, 150, 250);
    final img.Image upright = loadUpright(img.encodePng(source));
    final CameraFrame frame = frameFromImage(upright, DateTime.utc(2026));
    expect(frame.width, 2);
    expect(frame.height, 1);
    expect(frame.format, FrameFormat.bgra8888);
    expect(frame.rotationDegrees, 0);
    expect(frame.planes.single.bytesPerRow, 8);
    // B, G, R, A per pixel.
    expect(frame.planes.single.bytes.sublist(0, 3), <int>[30, 10, 200]);
    expect(frame.planes.single.bytes.sublist(4, 7), <int>[250, 150, 5]);
  });

  test('EXIF rotation is applied, as labelling tools show the photo', () {
    final img.Image stored = img.Image(width: 4, height: 2);
    // Orientation 6: the camera was held upright; the pixels are stored sideways.
    stored.exif.imageIfd.orientation = 6;
    final img.Image upright = loadUpright(img.encodeJpg(stored));
    expect(upright.width, 2);
    expect(upright.height, 4);
  });

  test('large photos are scaled to camera size, small ones are not', () {
    final img.Image big = img.Image(width: 4000, height: 3000);
    final img.Image scaled = toCameraSize(big, 720);
    expect(scaled.width, 720);
    expect(scaled.height, 540);

    final img.Image small = img.Image(width: 640, height: 480);
    expect(identical(toCameraSize(small, 720), small), isTrue);
  });

  test('an unreadable file fails clearly', () {
    expect(
      () => loadUpright(Uint8List.fromList(<int>[1, 2, 3])),
      throwsFormatException,
    );
  });

  test('the prediction record has normalized xyxy boxes', () {
    final Map<String, Object?> record = imageRecord(
      file: 'kitchen/1.jpg',
      width: 3000,
      height: 4000,
      inferenceMs: 12.34567,
      detections: <DetectionResult>[
        const DetectionResult(
          classId: 56,
          confidence: 0.8765432,
          box: Rect.fromLTRB(0.1, 0.2, 0.3, 0.4),
          position: HorizontalPosition.left,
        ),
      ],
    );
    expect(record['file'], 'kitchen/1.jpg');
    expect(record['inference_ms'], 12.346);
    final Map<String, Object?> d =
        (record['detections']! as List<Map<String, Object?>>).single;
    expect(d['class'], 56);
    expect(d['confidence'], 0.876543);
    expect(d['box'], <double>[0.1, 0.2, 0.3, 0.4]);
  });
}
