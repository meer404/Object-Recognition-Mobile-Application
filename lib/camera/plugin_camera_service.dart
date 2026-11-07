import 'dart:async';
import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../settings/app_settings.dart';
import 'camera_frame.dart' as model;
import 'camera_service.dart';

/// Converts a plugin image to our frame, or returns null for a pixel format
/// the pipeline cannot read (it is dropped rather than misread).
model.CameraFrame? frameFromCameraImage(
  CameraImage image, {
  required int rotationDegrees,
  required DateTime timestamp,
}) {
  final model.FrameFormat format;
  final int expectedPlanes;
  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
      format = model.FrameFormat.yuv420;
      expectedPlanes = 3;
    case ImageFormatGroup.bgra8888:
      format = model.FrameFormat.bgra8888;
      expectedPlanes = 1;
    case ImageFormatGroup.jpeg:
    case ImageFormatGroup.nv21:
    case ImageFormatGroup.unknown:
      return null;
  }
  if (image.planes.length != expectedPlanes) return null;
  return model.CameraFrame(
    width: image.width,
    height: image.height,
    format: format,
    planes: <model.FramePlane>[
      for (final Plane plane in image.planes)
        model.FramePlane(
          bytes: plane.bytes,
          bytesPerRow: plane.bytesPerRow,
          bytesPerPixel: plane.bytesPerPixel,
        ),
    ],
    timestamp: timestamp,
    rotationDegrees: rotationDegrees,
  );
}

/// Maps a `camera` plugin error code to a failure the app can explain.
///
/// Codes differ by platform (see the plugin README), so this matches loosely.
CameraFailure failureFromCameraCode(String code) {
  final String lower = code.toLowerCase();
  if (lower.contains('accessdenied') ||
      lower.contains('accessrestricted') ||
      lower.contains('permission')) {
    return CameraFailure.permissionDenied;
  }
  if (lower.contains('notfound') || lower.contains('nocamera')) {
    return CameraFailure.noCamera;
  }
  return CameraFailure.other;
}

/// Picks the camera the app points at the scene: the back camera, or failing
/// that the first one (e.g. a laptop in a debug browser run).
CameraDescription? chooseCamera(List<CameraDescription> cameras) {
  if (cameras.isEmpty) return null;
  for (final CameraDescription camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.back) return camera;
  }
  return cameras.first;
}

/// [CameraService] backed by the `camera` plugin. Audio is disabled, so no
/// microphone permission is ever requested.
class PluginCameraService implements CameraService {
  PluginCameraService({this.quality = CameraQuality.medium});

  final CameraQuality quality;
  final StreamController<model.CameraFrame> _frames =
      StreamController<model.CameraFrame>.broadcast();

  CameraController? _controller;
  int _rotationDegrees = 0;
  bool _streaming = false;
  bool _warnedAboutFormat = false;

  @override
  Stream<model.CameraFrame> get frames => _frames.stream;

  @override
  bool get isStreaming => _streaming;

  @override
  Future<void> initialize() async {
    if (_controller != null) return;
    final CameraController controller;
    try {
      final CameraDescription? camera = chooseCamera(await availableCameras());
      if (camera == null) {
        throw const CameraServiceException(CameraFailure.noCamera);
      }
      _rotationDegrees = camera.sensorOrientation;
      controller = CameraController(
        camera,
        _preset(quality),
        enableAudio: false,
        imageFormatGroup: _formatGroup(),
      );
    } on CameraException catch (e) {
      throw CameraServiceException(
        failureFromCameraCode(e.code),
        e.description,
      );
    }
    try {
      await controller.initialize();
      if (!kIsWeb) {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      }
    } on CameraException catch (e) {
      await controller.dispose();
      throw CameraServiceException(
        failureFromCameraCode(e.code),
        e.description,
      );
    }
    _controller = controller;
  }

  @override
  Future<void> start() async {
    if (_streaming) return;
    final CameraController? controller = _controller;
    if (controller == null) {
      throw StateError('initialize() must complete before start()');
    }
    try {
      await controller.startImageStream(_onImage);
    } on CameraException catch (e) {
      throw CameraServiceException(
        failureFromCameraCode(e.code),
        e.description,
      );
    }
    _streaming = true;
  }

  void _onImage(CameraImage image) {
    final model.CameraFrame? frame = frameFromCameraImage(
      image,
      rotationDegrees: _rotationDegrees,
      timestamp: DateTime.now(),
    );
    if (frame != null) {
      _frames.add(frame);
    } else if (!_warnedAboutFormat) {
      _warnedAboutFormat = true;
      developer.log(
        'dropping frames in unsupported format ${image.format.group}',
        name: 'camera',
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_streaming) return;
    _streaming = false;
    await _controller?.stopImageStream();
  }

  @override
  Future<void> release() async {
    await stop();
    final CameraController? controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  @override
  Widget buildPreview() {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final Size? size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    // previewSize is landscape; the app is locked to portrait. Crop to fill
    // the screen without distorting the image.
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await release();
    await _frames.close();
  }

  static ResolutionPreset _preset(CameraQuality quality) => switch (quality) {
    CameraQuality.low => ResolutionPreset.low,
    CameraQuality.medium => ResolutionPreset.medium,
    CameraQuality.high => ResolutionPreset.high,
  };

  static ImageFormatGroup? _formatGroup() {
    if (kIsWeb) return null;
    return defaultTargetPlatform == TargetPlatform.iOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.yuv420;
  }
}
