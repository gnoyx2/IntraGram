import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

String generateSecureToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64Url.encode(bytes);
}

bool constantTimeEquals(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  if (aBytes.length != bBytes.length) return false;
  var diff = 0;
  for (var i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff == 0;
}

// Dart는 메모리 고정이 안 돼서 최선만 함: 비밀은 우리 소유 Uint8List에만 두고 다 쓰면 0·랜덤·0으로 덮음.
// String(메시지 본문)은 못 지우니 참조만 빨리 끊음
final class SecureBytes {
  SecureBytes(this._bytes);

  SecureBytes.alloc(int length) : _bytes = Uint8List(length);

  factory SecureBytes.copy(List<int> source) {
    final copy = Uint8List(source.length);
    copy.setAll(0, source);
    return SecureBytes(copy);
  }

  Uint8List _bytes;
  bool _destroyed = false;

  static final Random _rng = Random.secure();

  // destroy 뒤에 접근하면 조용히 빈 값을 돌려주지 않고 StateError를 던짐
  Uint8List get bytes {
    if (_destroyed) {
      throw StateError('SecureBytes used after destroy()');
    }
    return _bytes;
  }

  int get length => _bytes.length;

  bool get isDestroyed => _destroyed;

  void destroy() {
    if (_destroyed) return;
    wipe(_bytes);
    _bytes = Uint8List(0);
    _destroyed = true;
  }

  // 0·랜덤·0 세 번 덮음 (0 채우기만 최적화하는 얼로케이터 대비). 못 고치는 리스트(cryptography SensitiveBytes 등)는
  // 그냥 둠: 라이브러리 키는 ownedSecretKeyFrom/takeSecretKey로 우리 버퍼에 옮겨야 지워짐
  static void wipe(List<int> target) {
    if (target.isEmpty) return;
    try {
      for (var i = 0; i < target.length; i++) {
        target[i] = 0;
      }
      for (var i = 0; i < target.length; i++) {
        target[i] = _rng.nextInt(256);
      }
      for (var i = 0; i < target.length; i++) {
        target[i] = 0;
      }
    } on UnsupportedError {
      // 수정 불가 버퍼는 소유한 쪽에서 지워야 함
    }
  }
}

final Type _modifiableUint8List = Uint8List(0).runtimeType;

// cryptography SecretKeyData는 기본값이면 destroy가 참조만 끊고, 켜도 수정 가능한 Uint8List일 때만 지움.
// 그 조건을 맞춘 우리 버퍼로 키를 쥠
SecretKeyData ownedSecretKeyFrom(Uint8List buffer) {
  var owned = buffer;
  if (!identical(buffer.runtimeType, _modifiableUint8List)) {
    owned = Uint8List.fromList(buffer);
    SecureBytes.wipe(buffer);
  }
  return SecretKeyData(owned, overwriteWhenDestroyed: true);
}

// 라이브러리가 만든 키(HKDF·X25519 결과)를 우리 사본으로 바꾸고 원본은 바로 버림 (원본 바이트는 GC 전까지 힙에 남음)
Future<SecretKeyData> takeSecretKey(SecretKey key) async {
  try {
    return ownedSecretKeyFrom(Uint8List.fromList(await key.extractBytes()));
  } finally {
    key.destroy();
  }
}
