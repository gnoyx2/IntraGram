import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'package:intragram/theme/tokens.dart';

// 켜진 카메라 미리보기를 화면에 꽉 채우고 가운데 조준틀과 아래 안내를 얹음
class ScannerFrame extends StatelessWidget {
  const ScannerFrame({
    required this.camera,
    required this.previewSize,
    required this.hint,
    required this.reticleSide,
    required this.reticleRadius,
    super.key,
  });

  final CameraController camera;
  final Size previewSize;
  final String hint;
  final double reticleSide;
  final double reticleRadius;

  @override
  Widget build(BuildContext context) {
    // previewSize는 센서 기준 가로라 세로 화면에선 뒤집어 채움(넘치는 쪽은 잘림)
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: portrait ? previewSize.height : previewSize.width,
              height: portrait ? previewSize.width : previewSize.height,
              child: CameraPreview(camera),
            ),
          ),
        ),
        Center(
          child: Container(
            width: reticleSide,
            height: reticleSide,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 3),
              borderRadius: BorderRadius.circular(reticleRadius),
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.xxl,
          right: AppSpacing.xxl,
          bottom: AppSpacing.huge,
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
