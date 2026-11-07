import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kurdish_vision/camera/camera_frame.dart';
import 'package:kurdish_vision/detection/detection_result.dart';

/// Decodes a photo and applies its EXIF orientation, so it is upright the way
/// labelling tools show it. Without this, boxes from a phone photo stored
/// sideways would not line up with the labels.
img.Image loadUpright(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('not a supported image');
  return img.bakeOrientation(decoded);
}

/// Scales [image] down so its longer side is at most [maxSide], as a camera
/// preview frame would be (D-023). Area averaging, like a camera's scaler.
/// Smaller images are returned unchanged.
img.Image toCameraSize(img.Image image, int maxSide) {
  final int longer = math.max(image.width, image.height);
  if (longer <= maxSide) return image;
  final double scale = maxSide / longer;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

/// The upright [image] as the BGRA frame an iPhone camera delivers. Rotation
/// is 0 because the image is already upright.
CameraFrame frameFromImage(img.Image image, DateTime timestamp) {
  final img.Image rgba = image.numChannels == 4
      ? image
      : image.convert(numChannels: 4);
  final Uint8List bgra = rgba.getBytes(order: img.ChannelOrder.bgra);
  return CameraFrame(
    width: image.width,
    height: image.height,
    format: FrameFormat.bgra8888,
    planes: <FramePlane>[FramePlane(bytes: bgra, bytesPerRow: image.width * 4)],
    timestamp: timestamp,
  );
}

/// One image's entry in predictions.json. Boxes are normalized `[x1, y1, x2, y2]`
/// of the upright image (scaling does not change normalized coordinates).
Map<String, Object?> imageRecord({
  required String file,
  required int width,
  required int height,
  required double inferenceMs,
  required List<DetectionResult> detections,
}) => <String, Object?>{
  'file': file,
  'width': width,
  'height': height,
  'inference_ms': double.parse(inferenceMs.toStringAsFixed(3)),
  'detections': <Map<String, Object?>>[
    for (final DetectionResult d in detections)
      <String, Object?>{
        'class': d.classId,
        'confidence': double.parse(d.confidence.toStringAsFixed(6)),
        'box': <double>[
          for (final double v in <double>[
            d.box.left,
            d.box.top,
            d.box.right,
            d.box.bottom,
          ])
            double.parse(v.toStringAsFixed(6)),
        ],
      },
  ],
};
