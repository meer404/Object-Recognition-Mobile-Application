import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../camera/camera_frame.dart';

/// Grey value of letterbox padding (Ultralytics' convention), 0–255.
const int letterboxPadValue = 114;

/// How an upright image of a given size sits inside the square model input.
/// Follows Ultralytics' LetterBox, including its rounding.
class LetterboxGeometry {
  factory LetterboxGeometry.forImage({
    required int width,
    required int height,
    required int inputSize,
  }) {
    final double scaleX = inputSize / width;
    final double scaleY = inputSize / height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;
    final int newWidth = (width * scale).round();
    final int newHeight = (height * scale).round();
    return LetterboxGeometry._(
      width: width,
      height: height,
      inputSize: inputSize,
      newWidth: newWidth,
      newHeight: newHeight,
      left: ((inputSize - newWidth) / 2 - 0.1).round(),
      top: ((inputSize - newHeight) / 2 - 0.1).round(),
    );
  }

  const LetterboxGeometry._({
    required this.width,
    required this.height,
    required this.inputSize,
    required this.newWidth,
    required this.newHeight,
    required this.left,
    required this.top,
  });

  /// Size of the upright image.
  final int width;
  final int height;
  final int inputSize;

  /// Size of the resized image inside the input.
  final int newWidth;
  final int newHeight;

  /// Padding before the resized image.
  final int left;
  final int top;

  /// Maps a box in input-normalized coordinates to normalized coordinates of
  /// the upright image, clamped to the image.
  Rect toUprightBox(double x1, double y1, double x2, double y2) {
    double map(double value, int offset, int length) =>
        ((value * inputSize - offset) / length).clamp(0.0, 1.0);
    return Rect.fromLTRB(
      map(x1, left, newWidth),
      map(y1, top, newHeight),
      map(x2, left, newWidth),
      map(y2, top, newHeight),
    );
  }
}

/// Width of [frame] once rotated upright.
int uprightWidth(CameraFrame frame) =>
    frame.rotationDegrees % 180 == 0 ? frame.width : frame.height;

/// Height of [frame] once rotated upright.
int uprightHeight(CameraFrame frame) =>
    frame.rotationDegrees % 180 == 0 ? frame.height : frame.width;

/// Converts [frame] to the model input: upright, letterboxed, RGB, 0–1, planar
/// `[R…, G…, B…]` (the tensor is NCHW `[1, 3, S, S]`).
///
/// Bilinear resize samples the 2×2 neighbourhood, like cv2.INTER_LINEAR. On 128
/// COCO images, nearest-neighbour lost 8–11 % of detections (D-019), so the extra
/// reads are worth it. Reuses [output] when given, to avoid per-frame garbage.
Float32List preprocessFrame(
  CameraFrame frame,
  LetterboxGeometry geometry, {
  Float32List? output,
}) {
  final int size = geometry.inputSize;
  final int plane = size * size;
  final Float32List tensor = (output != null && output.length == 3 * plane)
      ? output
      : Float32List(3 * plane);
  tensor.fillRange(0, tensor.length, letterboxPadValue / 255);

  final _Reader reader = switch (frame.format) {
    FrameFormat.yuv420 => _YuvReader(frame),
    FrameFormat.bgra8888 => _BgraReader(frame),
  };

  final int newWidth = geometry.newWidth;
  final int newHeight = geometry.newHeight;
  final int imageWidth = geometry.width;
  final int imageHeight = geometry.height;

  // Horizontal sample positions are the same for every row.
  final Int32List x0s = Int32List(newWidth);
  final Int32List x1s = Int32List(newWidth);
  final Float32List xWeights = Float32List(newWidth);
  for (int x = 0; x < newWidth; x++) {
    final double source = (x + 0.5) * imageWidth / newWidth - 0.5;
    final double clamped = source.clamp(0.0, imageWidth - 1.0);
    final int floor = clamped.floor();
    x0s[x] = floor;
    x1s[x] = floor + 1 < imageWidth ? floor + 1 : floor;
    xWeights[x] = clamped - floor;
  }

  const double toUnit = 1 / 255;
  for (int y = 0; y < newHeight; y++) {
    final double sourceY = ((y + 0.5) * imageHeight / newHeight - 0.5).clamp(
      0.0,
      imageHeight - 1.0,
    );
    final int y0 = sourceY.floor();
    final int y1 = y0 + 1 < imageHeight ? y0 + 1 : y0;
    final double wy = sourceY - y0;
    int index = (y + geometry.top) * size + geometry.left;
    for (int x = 0; x < newWidth; x++, index++) {
      final int topLeft = reader.rgbAt(x0s[x], y0);
      final int topRight = reader.rgbAt(x1s[x], y0);
      final int bottomLeft = reader.rgbAt(x0s[x], y1);
      final int bottomRight = reader.rgbAt(x1s[x], y1);
      final double wx = xWeights[x];
      tensor[index] =
          _blend(
            topLeft >> 16,
            topRight >> 16,
            bottomLeft >> 16,
            bottomRight >> 16,
            wx,
            wy,
          ) *
          toUnit;
      tensor[index + plane] =
          _blend(
            (topLeft >> 8) & 0xFF,
            (topRight >> 8) & 0xFF,
            (bottomLeft >> 8) & 0xFF,
            (bottomRight >> 8) & 0xFF,
            wx,
            wy,
          ) *
          toUnit;
      tensor[index + 2 * plane] =
          _blend(
            topLeft & 0xFF,
            topRight & 0xFF,
            bottomLeft & 0xFF,
            bottomRight & 0xFF,
            wx,
            wy,
          ) *
          toUnit;
    }
  }
  return tensor;
}

double _blend(int a, int b, int c, int d, double wx, double wy) {
  final double top = a + (b - a) * wx;
  final double bottom = c + (d - c) * wx;
  return top + (bottom - top) * wy;
}

/// Reads a pixel by UPRIGHT coordinates, as `0xRRGGBB`.
abstract class _Reader {
  _Reader(CameraFrame frame)
    : _width = frame.width,
      _height = frame.height,
      _rotation = frame.rotationDegrees % 360;

  final int _width;
  final int _height;
  final int _rotation;

  int rgbAt(int x, int y) => switch (_rotation) {
    // The sensor image is turned clockwise by this many degrees to be upright.
    90 => readSensor(y, _height - 1 - x),
    180 => readSensor(_width - 1 - x, _height - 1 - y),
    270 => readSensor(_width - 1 - y, x),
    _ => readSensor(x, y),
  };

  int readSensor(int x, int y);
}

class _BgraReader extends _Reader {
  _BgraReader(super.frame)
    : _bytes = frame.planes[0].bytes,
      _stride = frame.planes[0].bytesPerRow;

  final Uint8List _bytes;
  final int _stride;

  @override
  int readSensor(int x, int y) {
    final int i = y * _stride + x * 4;
    return (_bytes[i + 2] << 16) | (_bytes[i + 1] << 8) | _bytes[i];
  }
}

/// YUV_420_888 with any row and pixel stride, as Android may report them.
/// Full-range BT.601 in 8.8 fixed point, as Android camera output uses.
class _YuvReader extends _Reader {
  _YuvReader(super.frame)
    : _y = frame.planes[0].bytes,
      _yStride = frame.planes[0].bytesPerRow,
      _u = frame.planes[1].bytes,
      _v = frame.planes[2].bytes,
      _uvStride = frame.planes[1].bytesPerRow,
      _uvPixel = frame.planes[1].bytesPerPixel ?? 1;

  final Uint8List _y;
  final int _yStride;
  final Uint8List _u;
  final Uint8List _v;
  final int _uvStride;
  final int _uvPixel;

  @override
  int readSensor(int x, int y) {
    final int luma = _y[y * _yStride + x];
    final int chroma = (y >> 1) * _uvStride + (x >> 1) * _uvPixel;
    final int u = _u[chroma] - 128;
    final int v = _v[chroma] - 128;
    final int r = luma + ((359 * v) >> 8);
    final int g = luma - ((88 * u + 183 * v) >> 8);
    final int b = luma + ((454 * u) >> 8);
    return (_clamp(r) << 16) | (_clamp(g) << 8) | _clamp(b);
  }

  static int _clamp(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);
}
