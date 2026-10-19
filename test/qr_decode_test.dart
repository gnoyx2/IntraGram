import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/peer_code.dart';
import 'package:intragram/core/qr_decode.dart';

import 'support/qr_frames.dart';

// 스캐너는 ML Kit 없이 순수 Dart로 QR을 읽음: 카메라 Y 평면처럼 줄 끝이 채워진 프레임에서도 가운데 QR을
// 읽고, QR이 없으면 null
void main() {
  test('reads a device code from a padded camera frame', () {
    final code = deviceCode(
      host: '192.168.1.20',
      port: 7890,
      peerId: '0123456789abcdef0123456789abcdef',
    );
    expect(decodeQr(qrFrame(code)), code);
    expect(decodeQr(qrFrame(code, width: 720, padding: 0, scale: 5)), code);
  });

  test('a frame without a code gives null', () {
    final blank = Uint8List(640 * 480)..fillRange(0, 640 * 480, 128);
    expect(
      decodeQr(QrFrame(luma: blank, width: 640, height: 480, rowStride: 640)),
      isNull,
    );
  });
  // 카메라 잡음에선 zxing2가 읽기 실패 대신 ArgumentError(버전 번호 등)를 던지기도 함: 그래도 null
  test('noisy frames never throw', () {
    final random = Random(7);
    for (var i = 0; i < 180; i++) {
      final noise = Uint8List.fromList(
        List<int>.generate(640 * 480, (_) => random.nextInt(256)),
      );
      expect(
        () => decodeQr(
          QrFrame(luma: noise, width: 640, height: 480, rowStride: 640),
        ),
        returnsNormally,
        reason: 'frame $i',
      );
    }
  });
}
