import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/camera/camera_frame.dart' as model;
import 'package:kurdish_vision/camera/camera_service.dart';
import 'package:kurdish_vision/camera/plugin_camera_service.dart';

CameraImage _image(ImageFormatGroup group, int planes) =>
    CameraImage.fromPlatformInterface(
      CameraImageData(
        format: CameraImageFormat(group, raw: 0),
        width: 640,
        height: 480,
        planes: <CameraImagePlane>[
          for (int i = 0; i < planes; i++)
            CameraImagePlane(
              bytes: Uint8List.fromList(<int>[i]),
              bytesPerRow: 640 + i,
              bytesPerPixel: i + 1,
            ),
        ],
      ),
    );

CameraDescription _camera(String name, CameraLensDirection direction) =>
    CameraDescription(
      name: name,
      lensDirection: direction,
      sensorOrientation: 90,
    );

void main() {
  final DateTime when = DateTime.utc(2026, 11, 7);

  group('frameFromCameraImage', () {
    test('keeps all three YUV planes in order', () {
      final model.CameraFrame frame = frameFromCameraImage(
        _image(ImageFormatGroup.yuv420, 3),
        rotationDegrees: 90,
        timestamp: when,
      )!;
      expect(frame.format, model.FrameFormat.yuv420);
      expect(frame.width, 640);
      expect(frame.height, 480);
      expect(frame.rotationDegrees, 90);
      expect(frame.timestamp, when);
      expect(frame.planes, hasLength(3));
      expect(frame.planes[2].bytes, <int>[2]);
      expect(frame.planes[1].bytesPerRow, 641);
      expect(frame.planes[1].bytesPerPixel, 2);
    });

    test('accepts single-plane BGRA', () {
      final model.CameraFrame? frame = frameFromCameraImage(
        _image(ImageFormatGroup.bgra8888, 1),
        rotationDegrees: 0,
        timestamp: when,
      );
      expect(frame?.format, model.FrameFormat.bgra8888);
    });

    test('drops formats and plane counts it cannot read', () {
      for (final CameraImage image in <CameraImage>[
        _image(ImageFormatGroup.jpeg, 1),
        _image(ImageFormatGroup.nv21, 2),
        _image(ImageFormatGroup.unknown, 1),
        _image(ImageFormatGroup.yuv420, 2),
        _image(ImageFormatGroup.bgra8888, 3),
      ]) {
        expect(
          frameFromCameraImage(image, rotationDegrees: 0, timestamp: when),
          isNull,
        );
      }
    });
  });

  group('uprightRotation', () {
    test('a landscape sensor frame uses the sensor orientation', () {
      expect(
        uprightRotation(width: 640, height: 480, sensorOrientation: 90),
        90,
      );
    });

    test('a frame that is already portrait is not rotated again', () {
      expect(
        uprightRotation(width: 480, height: 640, sensorOrientation: 90),
        0,
      );
    });
  });

  group('failureFromCameraCode', () {
    test('permission codes from the plugin README', () {
      for (final String code in <String>[
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      ]) {
        expect(failureFromCameraCode(code), CameraFailure.permissionDenied);
      }
    });

    test('missing camera', () {
      expect(failureFromCameraCode('cameraNotFound'), CameraFailure.noCamera);
    });

    test('anything else is a general failure', () {
      expect(failureFromCameraCode('IOError'), CameraFailure.other);
    });
  });

  group('chooseCamera', () {
    test('prefers the back camera', () {
      expect(
        chooseCamera(<CameraDescription>[
          _camera('front', CameraLensDirection.front),
          _camera('back', CameraLensDirection.back),
        ])?.name,
        'back',
      );
    });

    test('falls back to the first camera', () {
      expect(
        chooseCamera(<CameraDescription>[
          _camera('usb', CameraLensDirection.external),
        ])?.name,
        'usb',
      );
    });

    test('no cameras gives null', () {
      expect(chooseCamera(<CameraDescription>[]), isNull);
    });
  });
}
