import 'dart:typed_data';

/// Pixel layout of a [CameraFrame].
enum FrameFormat {
  /// Android: three planes (Y, U, V).
  yuv420,

  /// iOS: one interleaved plane.
  bgra8888,
}

/// One plane of raw image data.
class FramePlane {
  const FramePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
}

/// A platform-neutral camera frame.
///
/// It decouples the pipeline from the `camera` plugin's `CameraImage`, so
/// detectors can be unit-tested with synthetic frames. It holds only
/// primitive data, so it can be sent to a background isolate.
class CameraFrame {
  const CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    required this.timestamp,
    this.rotationDegrees = 0,
  });

  final int width;
  final int height;
  final FrameFormat format;
  final List<FramePlane> planes;

  /// When the frame was received from the camera stream.
  final DateTime timestamp;

  /// Sensor rotation needed to make the frame upright (0/90/180/270).
  final int rotationDegrees;
}
