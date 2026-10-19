import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/secure_bytes.dart';
import 'package:intragram/network/sas_generator.dart';

export 'package:intragram/network/sas_generator.dart';

part 'crypto_engine/handshake.dart';
part 'crypto_engine/message_records.dart';
part 'crypto_engine/file_records.dart';

// 앱-앱 피어 링크용 로컬 E2E 암호화
// - X25519, 링크마다 새 임시 키페어 (forward secrecy). DH 결과가 전부 0이거나 두 공개키가 같으면 거부
// - HKDF-SHA256으로 방향별 키 4개 (메시지/파일 채널 x 양방향). salt는
// 정렬한 두 공개키라 반사해도 안 열림. SAS는 별도 출력(kSasInfo)
// - ChaCha20-Poly1305, nonce = 4바이트 0 + 8바이트 BE 카운터 (메시지는
// PeerLink의 아웃바운드 seq, 파일은 세션 자체 카운터). 파일은 별도 서브키
// - 장기 키 없음. 신원 키(Ed25519, 메모리에만)는 peerId 증명에만 쓰고 세션 키 합의엔 관여 안 함

// 선택적 PIN 보관소의 KDF 반복 횟수. 짧은 PIN은 저엔트로피라 파일을 손에 넣은 공격자에게 200k 반복은 완화책이지 보장이 아님
const int kVaultPbkdf2Iterations = 200000;
const int kVaultLegacyPbkdf2Iterations = 100000;

final class CryptoEngine {
  final X25519 _kex = X25519();
  final Chacha20 _aead = Chacha20.poly1305Aead();

  // 기본 200k, 구형 파일 판독 때만 100k로 32바이트 vault 키 유도함
  // 한계: PIN은 저엔트로피라 반복 횟수는 완화책일 뿐 보장이 아님.
  // Argon2id는 cryptography v2에 있지만 v1.0 vault 파일 호환을 위해 PBKDF2를 유지함.
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

  // 메시지/파일 채널 각각 송신용/수신용 키가 따로 있음 (CryptoSessionHandshake 참고)
  // _msgSendTag/_msgRecvTag는 AEAD associated data에 박는 짧은 방향 태그
  SecretKey? _msgSendKey;
  SecretKey? _msgRecvKey;
  SecretKey? _fileSendKey;
  SecretKey? _fileRecvKey;
  String? _msgSendTag;
  String? _msgRecvTag;

  // 파일 청크 송신 nonce 카운터. 방향별 키라 메시지 채널 seq와 겹쳐도 무해함
  // await 전에 예약해서 동시 호출이 겹쳐도 안 겹침
  int _fileSendCounter = 0;

  // 메시지 채널에서 마지막으로 seal에 쓰인 seq. 호출부가 직렬 큐로 순서를 보장하지만
  // 세션도 같은 seq(= 같은 nonce) 재사용을 거부함 (호출부 버그 하나가 (key, nonce) 쌍을 두 번 쓰게 두지 않음)
  int _lastSealedSeq = -1;

  // completeHandshake 동시 호출을 하나로 합침 (두 번째 호출은 새 DH/HKDF 대신 첫 번째 Future를 기다림)
  Future<void>? _handshakeInFlight;

  String? _sasDigits;
  bool _destroyed = false;

  bool get isReady => _msgSendKey != null && !_destroyed;

  String get publicKeyBase64 => base64.encode(publicKey);

  // 핸드셰이크가 끝나면 양쪽 피어가 동일. 비밀이 아님 (소리 내어 읽거나 화면으로 맞춰보라고 만든 값)
  String? get sasDigits => _sasDigits;

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

  // 세션 키 4개는 앱 소유 버퍼라 0으로 덮임. X25519 키페어는 라이브러리가 참조만 끊음
  // (개인키 바이트 덮어쓰기 보장 없음, GC 전까지 힙에 남을 수 있음). 멱등
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _sasDigits = null;
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
