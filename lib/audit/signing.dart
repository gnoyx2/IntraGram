import 'dart:math';
import 'dart:typed_data';

import 'package:intragram/network/peer_auth.dart'
    show isSmallOrderKey, verifyAuth;

final Random _rng = Random.secure();

Uint8List immutableBytes(List<int> bytes) =>
    Uint8List.fromList(bytes).asUnmodifiableView();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (_) => _rng.nextInt(256)));

// 증적·배치·앵커·자격·작성자 서명이 다 쓰는 Ed25519 검사. 작은 위수 키는 아무 메시지에 통하는 서명이 만들어져서
// 거부하고(핸드셰이크와 같은 규칙) 길이가 틀린 키·서명도 던지지 않고 false
Future<bool> verifyEd25519({
  required List<int> message,
  required List<int> signature,
  required List<int> key,
}) async {
  if (key.length != 32 || signature.length != 64 || isSmallOrderKey(key)) {
    return false;
  }
  try {
    return await verifyAuth(
      transcript: message,
      signature: signature,
      signerKey: key,
    );
  } on ArgumentError {
    return false;
  }
}
