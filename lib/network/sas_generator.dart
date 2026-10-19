import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/secure_bytes.dart';

// X25519 공유 비밀에서 6자리 SAS를 유도. 세션 키와 다른 HKDF info(kSasInfo)로
// 별도 서브키를 뽑아 domain separation (어느 채널과도 키 공유 안 함)
// transcript는 두 핸드셰이크 공개키를 정렬한 바이트(순서 무관)로 salt에 써서 이 핸드셰이크 쌍에 묶음. 같은 shared
// secret이면 항상 같은 6자리라 소리 내어 맞춰보면 다른 shared secret을 가진 active MITM을 잡아냄
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

// [0, 1000000) 균등분포에서 안 쓰는 꼬리 구간: 2^32가 1,000,000의 배수가 아니라 단순히 % 1000000 하면
// 일부 조합이 약 0.02% 더 자주 나옴. 레인(4바이트)이 이 구간에 걸리면 버리고 다음 레인으로
const int _kRejectThreshold = (0x100000000 ~/ 1000000) * 1000000;

// 32바이트(4바이트 레인 8개)를 편향 없는 6자리로 매핑. 순수 함수라 테스트에서 HKDF 없이 바이트를 직접 넣어볼 수 있음
// 8레인 전부 거부될 확률은 사실상 0(약 10^-35)이지만 나오면 조용히 편향된 값을 주느니 던짐
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
