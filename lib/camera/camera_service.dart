import 'package:flutter/widgets.dart';

import 'camera_frame.dart';

/// Why the camera could not be used.
enum CameraFailure { permissionDenied, noCamera, other }

/// Thrown by [CameraService] when the camera cannot be opened or streamed.
class CameraServiceException implements Exception {
  const CameraServiceException(this.failure, [this.detail]);

  final CameraFailure failure;
  final String? detail;

  @override
  String toString() => 'CameraServiceException(${failure.name}: $detail)';
}

/// Abstraction over the device camera.
///
/// Frames are processed on-device only and are never persisted unless
/// evaluation mode is enabled.
abstract class CameraService {
  /// Requests permission and opens the back camera. Does nothing if already
  /// open, and may be called again after [release].
  ///
  /// Throws [CameraServiceException].
  Future<void> initialize();

  /// Frames, while streaming. Stays usable across [release]/[initialize].
  Stream<CameraFrame> get frames;

  /// Whether the camera is open and streaming.
  bool get isStreaming;

  /// Starts the image stream. Requires [initialize]. Does nothing if already
  /// streaming.
  Future<void> start();

  /// Stops the image stream but keeps the camera open (the user paused).
  Future<void> stop();

  /// Closes the camera so other apps can use it (the app left the screen).
  Future<void> release();

  /// Live preview. Only meaningful between [initialize] and [release].
  Widget buildPreview();

  /// Releases everything. The service cannot be used afterwards.
  Future<void> dispose();
}
