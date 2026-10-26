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

// 2^32가 1,000,000의 배수가 아니라 그냥 % 하면 일부 숫자가 약 0.02% 더 자주 나옴: 이 위 구간에 걸린 레인은 버리고 다음 레인
const int _kRejectThreshold = (0x100000000 ~/ 1000000) * 1000000;

// 32바이트(4바이트 레인 8개)를 편향 없는 6자리로. 8레인 다 버려질 확률은 약 10^-35지만 나오면 편향된 값 대신 던짐
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
