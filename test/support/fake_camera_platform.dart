import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';

import 'package:intragram/core/qr_decode.dart';

// 카메라 플러그인의 네이티브 쪽 대신: 뒤 카메라 하나, 권한 거부 흉내, 테스트가 넣는 프레임 스트림.
// 만든·닫은 카메라 수를 세서 화면이 카메라를 언제 쥐고 놓는지 봄
class FakeCameraPlatform extends CameraPlatform {
  // true면 카메라를 만들 때 권한 거부 (Android·iOS의 CameraAccessDenied)
  bool denied = false;
  // 카메라를 만들려 한 횟수(거부 포함)와 실제로 만든·닫은 수
  int attempts = 0;
  int created = 0;
  int disposed = 0;
  // 걸어 두면 카메라 목록이 이게 끝날 때까지 안 옴 (목록을 기다리는 사이의 경합 흉내)
  Completer<void>? camerasGate;
  final StreamController<CameraImageData> _frames =
      StreamController<CameraImageData>.broadcast();
  final StreamController<CameraInitializedEvent> _initialized =
      StreamController<CameraInitializedEvent>.broadcast();

  bool get streaming => _frames.hasListener;

  void addFrame(QrFrame frame) => _frames.add(
    CameraImageData(
      format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
      width: frame.width,
      height: frame.height,
      planes: [
        CameraImagePlane(
          bytes: frame.luma,
          bytesPerRow: frame.rowStride,
          bytesPerPixel: 1,
        ),
      ],
    ),
  );

  @override
  Future<List<CameraDescription>> availableCameras() async {
    await camerasGate?.future;
    return const [
      CameraDescription(
        name: 'back',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async {
    attempts++;
    if (denied) throw CameraException('CameraAccessDenied', 'denied');
    return ++created;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    scheduleMicrotask(
      () => _initialized.add(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream.where((e) => e.cameraId == cameraId);

  // 안 닫히는 빈 스트림 (컨트롤러가 .first로 기다림)
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>.broadcast().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => _frames.stream;

  @override
  Widget buildPreview(int cameraId) =>
      const ColoredBox(key: ValueKey('camera-preview'), color: Colors.green);

  @override
  Future<void> dispose(int cameraId) async => disposed++;
}
