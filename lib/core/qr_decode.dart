import 'dart:math' show min;
import 'dart:typed_data';

import 'package:zxing2/qrcode.dart';

// 카메라 프레임 한 장의 밝기(Y) 평면 사본 (카메라 버퍼는 콜백 뒤 재사용돼서 복사해 isolate로 넘김).
// rowStride는 줄 끝 채움 때문에 width보다 클 수 있음
final class QrFrame {
  const QrFrame({
    required this.luma,
    required this.width,
    required this.height,
    required this.rowStride,
  });

  final Uint8List luma;
  final int width;
  final int height;
  final int rowStride;
}

// 조준틀 자리(가운데 정사각형)에서 QR 하나를 읽음. 순수 Dart(ZXing 이식)라 진단을 올리는 구성 요소가 없음
String? decodeQr(QrFrame frame) {
  final side = (min(frame.width, frame.height) * 0.8).floor();
  if (side < 21) return null; // 가장 작은 QR(21모듈)도 안 들어감
  try {
    return QRCodeReader()
        .decode(
          BinaryBitmap(HybridBinarizer(_CenterSquare(frame, side))),
          hints: DecodeHints()..put(DecodeHintType.tryHarder),
        )
        .text;
  } on ReaderException {
    return null;
  } on Error {
    // 잡음 프레임이면 zxing2가 읽기 실패 대신 ArgumentError·RangeError·UnsupportedError를 던지기도 함. 프레임마다 다시 하니 다 '코드 없음'으로 침
    return null;
  }
}

// 가운데 side×side 밝기만 줄 끝 채움 없이 한 덩어리로 복사해 둠
final class _CenterSquare extends LuminanceSource {
  _CenterSquare(QrFrame frame, int side)
    : _pixels = Int8List(side * side),
      super(side, side) {
    final left = (frame.width - side) ~/ 2;
    final top = (frame.height - side) ~/ 2;
    for (var y = 0; y < side; y++) {
      final from = (top + y) * frame.rowStride + left;
      _pixels.setRange(y * side, (y + 1) * side, frame.luma, from);
    }
  }

  final Int8List _pixels;

  @override
  Int8List getRow(int y, Int8List? row) {
    final out = row != null && row.length >= width ? row : Int8List(width);
    out.setRange(0, width, _pixels, y * width);
    return out;
  }

  @override
  Int8List getMatrix() => _pixels;
}
