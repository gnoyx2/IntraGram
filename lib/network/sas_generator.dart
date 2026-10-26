import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/secure_bytes.dart';

// 공유 비밀에서 6자리 SAS를 뽑음 (세션 키와 다른 HKDF info라 어느 채널과도 키 안 겹침). salt는 정렬한 두 공개키라
// 같은 핸드셰이크면 늘 같은 숫자고, 공유 비밀이 다른 중간자는 숫자가 달라서 걸림
Future<String> deriveSasDigits(
  SecretKey sharedSecret, {
  required List<int> transcript,
}) async {
  final sasKdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final sasKey = await takeSecretKey(
    await sasKdf.deriveKey(
      secretKey: sharedSecret,
      nonce: transcript,
      info: utf8.encode(kSasInfo),
    ),
  );
  try {
    return digitsFromBytes(sasKey.bytes);
  } finally {
    sasKey.destroy();
  }
}

// 2^32가 1,000,000의 배수가 아니므로 단순 나머지 연산 시 일부 숫자의 출현 빈도가 높아짐: 임계값 이상인 레인은 기각하고 다음 레인으로 진행함
const int _kRejectThreshold = (0x100000000 ~/ 1000000) * 1000000;

// 32바이트(4바이트 레인 8개)에서 편향 없는 6자리 숫자를 추출함. 8개 레인이 모두 기각될 확률은 극히 낮으나 발생 시 편향된 값 대신 예외를 던짐
@visibleForTesting
String digitsFromBytes(List<int> bytes) {
  for (var offset = 0; offset + 4 <= bytes.length; offset += 4) {
    var value = 0;
    for (final b in bytes.skip(offset).take(4)) {
      value = (value << 8) | (b & 0xff);
    }
    if (value < _kRejectThreshold) {
      return (value % 1000000).toString().padLeft(6, '0');
    }
  }
  throw StateError('SAS reject-sampling exhausted ${bytes.length} bytes');
}
