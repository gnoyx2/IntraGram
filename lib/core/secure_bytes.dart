import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// 포털 입장 토큰, 파일 전송 GET/POST 인가 토큰 등 일회용 비밀 발급에 공용으로 씀
String generateSecureToken() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64Url.encode(bytes);
}

// 타이밍 어택 방지용 상수 시간 비교 (같은 길이면 첫 불일치에서 안 멈추고 끝까지 XOR 누적)
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

// Dart는 메모리 고정이나 GC의 객체 복사 방지를 못 해서 최선만 함: 시크릿은 우리가 소유한
// Uint8List에만 담고(String은 불변이라 스크럽 불가), 필요 없어지면 즉시 0x00 -> 랜덤 -> 0x00으로 덮음
// UI를 지나가는 String(메시지 본문)은 못 지우므로 수명을 최소화하고 표시 + TTL 이후엔 안 들고 있음
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

  // destroy 이후엔 던짐. use-after-free가 조용히 스크럽된 데이터로 동작하지 않고 시끄럽게 터지게 함
  Uint8List get bytes {
    if (_destroyed) {
      throw StateError('SecureBytes used after destroy()');
    }
    return _bytes;
  }

  int get length => _bytes.length;

  bool get isDestroyed => _destroyed;

  // 멱등
  void destroy() {
    if (_destroyed) return;
    wipe(_bytes);
    _bytes = Uint8List(0);
    _destroyed = true;
  }

  // 0, 랜덤, 0 3패스. 랜덤 패스는 0 채우기만 특수 처리하는 얼로케이터를 무력화하고,
  // 마지막 0 패스는 키 재료를 안 남김
  // 수정 불가능한 리스트(cryptography의 SensitiveBytes 등)는 못 덮으니 던지지 않고 놔둠.
  // 라이브러리 키는 ownedSecretKeyFrom/takeSecretKey로 앱 소유 버퍼에 옮겨 써야 지워짐
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
      // 수정 불가능한 버퍼의 스크럽은 소유자 책임
    }
  }
}

final Type _modifiableUint8List = Uint8List(0).runtimeType;

// cryptography의 SecretKeyData는 기본값(overwriteWhenDestroyed: false)이라 destroy가 참조만 끊고,
// 켜도 정확히 수정 가능한 Uint8List일 때만 지움. 그 조건을 맞춘 앱 소유 버퍼로 키를 쥠
SecretKeyData ownedSecretKeyFrom(Uint8List buffer) {
  var owned = buffer;
  if (!identical(buffer.runtimeType, _modifiableUint8List)) {
    owned = Uint8List.fromList(buffer);
    SecureBytes.wipe(buffer);
  }
  return SecretKeyData(owned, overwriteWhenDestroyed: true);
}

// 라이브러리가 만든 키(HKDF·X25519 결과)를 앱 소유 사본으로 바꾸고 원본은 즉시 버림.
// 원본 바이트는 라이브러리가 안 지워서 GC 전까지 힙에 남음(최선 노력)
Future<SecretKeyData> takeSecretKey(SecretKey key) async {
  try {
    return ownedSecretKeyFrom(Uint8List.fromList(await key.extractBytes()));
  } finally {
    key.destroy();
  }
}
