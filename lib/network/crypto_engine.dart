import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/secure_bytes.dart';
import 'package:intragram/network/sas_generator.dart';

export 'package:intragram/network/sas_generator.dart';

part 'crypto_engine/handshake.dart';
part 'crypto_engine/message_records.dart';
part 'crypto_engine/file_records.dart';

// 앱끼리 링크 암호: 링크마다 새 X25519 키(전방 비밀성) → HKDF-SHA256으로 방향별 키 4개(메시지·파일 × 양방향)와 SAS.
// ChaCha20-Poly1305 nonce = 0 4바이트 + 8바이트 카운터(메시지는 PeerLink seq, 파일은 세션 카운터).
// 신원 키(Ed25519, 메모리만)는 peerId 증명에만 쓰고 키 합의엔 안 섞임

// 보관소 PIN KDF 반복 횟수. 짧은 PIN이면 파일을 가져간 사람한테 시간만 벌어 줌
const int kVaultPbkdf2Iterations = 200000;
const int kVaultLegacyPbkdf2Iterations = 100000;

final class CryptoEngine {
  final X25519 _kex = X25519();
  final Chacha20 _aead = Chacha20.poly1305Aead();

  // 기본 200k, 옛 파일 읽을 때만 100k. Argon2id도 있지만 v1.0 보관 파일 호환 때문에 PBKDF2 유지
  static Future<SecretKey> deriveKeyFromPin(
    String pin,
    List<int> salt, {
    int iterations = kVaultPbkdf2Iterations,
  }) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
  }

  Future<CryptoSession> createSession() async {
    final keyPair = await _kex.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return CryptoSession._(this, keyPair, Uint8List.fromList(publicKey.bytes));
  }
}

final class CryptoSession {
  CryptoSession._(this._engine, this._keyPair, this.publicKey);

  final CryptoEngine _engine;
  final SimpleKeyPair _keyPair;

  final Uint8List publicKey;

  // _msgSendTag·_msgRecvTag는 AAD에 박는 짧은 방향 태그
  SecretKey? _msgSendKey;
  SecretKey? _msgRecvKey;
  SecretKey? _fileSendKey;
  SecretKey? _fileRecvKey;
  String? _msgSendTag;
  String? _msgRecvTag;

  // 파일 청크 nonce 카운터. 키가 따로라 메시지 seq와 겹쳐도 상관없음
  int _fileSendCounter = 0;

  // 마지막으로 seal한 seq. 호출부 큐가 순서를 지켜도 세션도 같은 seq(=nonce) 재사용을 한 번 더 막음
  int _lastSealedSeq = -1;

  // completeHandshake 동시 호출은 이 Future 하나를 같이 기다림
  Future<void>? _handshakeInFlight;

  String? _sasDigits;
  Uint8List? _sessionBinding;
  bool _destroyed = false;

  bool get isReady => _msgSendKey != null && !_destroyed;

  String get publicKeyBase64 => base64.encode(publicKey);

  // 양쪽이 같은 값. 비밀 아님 (소리 내어 맞춰 보라고 만든 숫자)
  String? get sasDigits => _sasDigits;

  // 이 핸드셰이크의 두 임시키 해시 (양쪽 같음). 증명을 다른 세션으로 옮겨 쓰지 못하게 서명에 묶는 값
  Uint8List? get sessionBinding => _destroyed ? null : _sessionBinding;

  SecretKey _requireSendKey() {
    final key = _msgSendKey;
    if (key == null || _destroyed) {
      throw StateError('CryptoSession used before handshake / after destroy');
    }
    return key;
  }

  SecretKey _requireRecvKey() {
    final key = _msgRecvKey;
    if (key == null || _destroyed) {
      throw StateError('CryptoSession used before handshake / after destroy');
    }
    return key;
  }

  @visibleForTesting
  List<SecretKey?> get debugSessionKeys => [
    _msgSendKey,
    _msgRecvKey,
    _fileSendKey,
    _fileRecvKey,
  ];

  // 세션 키 4개는 우리 버퍼라 0으로 덮임. X25519 키쌍은 라이브러리가 참조만 끊어서 GC 전까지 힙에 남을 수 있음
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _sasDigits = null;
    _sessionBinding = null;
    _keyPair.destroy();
    _msgSendKey?.destroy();
    _msgSendKey = null;
    _msgRecvKey?.destroy();
    _msgRecvKey = null;
    _fileSendKey?.destroy();
    _fileSendKey = null;
    _fileRecvKey?.destroy();
    _fileRecvKey = null;
  }
}
