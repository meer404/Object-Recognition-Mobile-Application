import 'camera_frame.dart';

/// Abstraction over the device camera.
///
/// Implemented in Phase 2 on top of the `camera` plugin (image stream:
/// YUV420 on Android, BGRA8888 on iOS). Frames are processed on-device only
/// and are never persisted unless evaluation mode is enabled.
abstract class CameraService {
  /// Requests permission and opens the back camera.
  Future<void> initialize();

  /// Continuous stream of frames while [start] is active.
  Stream<CameraFrame> get frames;

  /// Whether the camera is open and streaming.
  bool get isStreaming;

  /// Starts the image stream.
  Future<void> start();

  /// Stops the image stream (e.g. on pause or app backgrounding).
  Future<void> stop();

  /// Releases the camera.
  Future<void> dispose();
}
