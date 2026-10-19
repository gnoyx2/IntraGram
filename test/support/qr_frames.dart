import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

import 'package:intragram/core/qr_decode.dart';

// 흰 바탕(밝기 235)에 검은 모듈(20) QR을 가운데 그린 카메라 Y 평면. 모듈 한 칸 = scale 픽셀,
// 줄 끝은 padding 바이트 (실제 카메라처럼 rowStride가 width보다 큼)
QrFrame qrFrame(
  String text, {
  int width = 640,
  int height = 480,
  int padding = 32,
  int scale = 6,
}) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  final stride = width + padding;
  final luma = Uint8List(stride * height)..fillRange(0, stride * height, 235);
  final size = matrix.width * scale;
  final left = (width - size) ~/ 2;
  final top = (height - size) ~/ 2;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (matrix.get(x ~/ scale, y ~/ scale) == 1) {
        luma[(top + y) * stride + left + x] = 20;
      }
    }
  }
  return QrFrame(luma: luma, width: width, height: height, rowStride: stride);
}
