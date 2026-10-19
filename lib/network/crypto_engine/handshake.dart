part of '../crypto_engine.dart';

const String _kDirLowToHigh = 'l2h';
const String _kDirHighToLow = 'h2l';

extension CryptoSessionHandshake on CryptoSession {
  // 동시 호출은 같은 in-flight Future를 기다려서 DH/HKDF를 또 안 돌림. 이미 끝났으면(성공/파괴) 즉시 반환
  // 피어 키가 전부 0인 shared secret을 만들거나(low-order point 공격) 우리 공개키를 그대로 돌려보내면
  // (자기 자신과의 핸드셰이크 흉내) SecurityException, 키가 깨졌으면 FormatException
  Future<void> completeHandshake(String peerPublicKeyBase64) {
    if (_destroyed || _msgSendKey != null) return Future<void>.value();
    return _handshakeInFlight ??= _completeHandshakeOnce(
      peerPublicKeyBase64,
    ).whenComplete(() => _handshakeInFlight = null);
  }

  Future<void> _completeHandshakeOnce(String peerPublicKeyBase64) async {
    final peerBytes = base64.decode(peerPublicKeyBase64);
    if (peerBytes.length != 32) {
      throw const FormatException('peer X25519 public key must be 32 bytes');
    }
    if (_constantTimeEquals(publicKey, peerBytes)) {
      throw SecurityException(
        'rejected handshake: peer echoed our own public key',
      );
    }

    final SecretKey libraryShared;
    try {
      libraryShared = await _engine._kex.sharedSecretKey(
        keyPair: _keyPair,
        remotePublicKey: SimplePublicKey(peerBytes, type: KeyPairType.x25519),
      );
    } on ArgumentError {
      throw SecurityException('rejected handshake: invalid peer public key');
    }
    // 라이브러리 결과는 destroy가 안 덮어서 앱 소유 사본으로 바꿔 쥠 (아래 키들도 같은 방식)
    final sharedSecret = await takeSecretKey(libraryShared);

    // 유도되는 키 전부(성공/실패/파괴 무관)를 이 try/finally가 덮음: 중간에 예외가 나도 지금까지 뽑은 키가
    // 스크럽 안 된 채 GC를 기다리지 않음. 성공 경로는 필드에 대입한 직후 로컬 참조를 비워 finally가 다시 안 지움
    SecretKey? lowToHigh;
    SecretKey? highToLow;
    SecretKey? fileLowToHigh;
    SecretKey? fileHighToLow;
    try {
      // contributory-behaviour 검사: 피어가 low-order point를
      // 강제하면 shared secret이 전부 0 (RFC 7748 §6.1). 세션 거부
      final sharedBytes = await sharedSecret.extractBytes();
      if (sharedBytes.every((b) => b == 0)) {
        throw SecurityException(
          'rejected handshake: all-zero shared secret (low-order point)',
        );
      }

      // 두 공개키를 사전순 정렬해 transcript로 고정 (HKDF salt): 유도되는 키 전부가 이 핸드셰이크 쌍에 묶임
      // 내 키가 정렬에서 앞(low)인지 뒤(high)인지로 송/수신 방향을 정하니 양쪽이 값을 주고받을 필요가 없음
      final iAmLow = _lexicographicCompare(publicKey, peerBytes) < 0;
      final transcript = <int>[
        ...utf8.encode(kProtocolVersion),
        ...(iAmLow ? publicKey : peerBytes),
        ...(iAmLow ? peerBytes : publicKey),
      ];

      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      Future<SecretKey> derive(String info) async => takeSecretKey(
        await hkdf.deriveKey(
          secretKey: sharedSecret,
          nonce: transcript,
          info: utf8.encode(info),
        ),
      );

      lowToHigh = await derive(kMessageKdfInfoLowToHigh);
      highToLow = await derive(kMessageKdfInfoHighToLow);
      fileLowToHigh = await derive(kFileKdfInfoLowToHigh);
      fileHighToLow = await derive(kFileKdfInfoHighToLow);
      final sas = await deriveSasDigits(sharedSecret, transcript: transcript);

      if (_destroyed) {
        // await 중 링크가 닫힘: 방금 뽑은 키를 필드에 대입하지 않고(finally가 destroy) 좀비 세션이 안 되게 함
        return;
      }

      if (iAmLow) {
        _msgSendKey = lowToHigh;
        _msgRecvKey = highToLow;
        _fileSendKey = fileLowToHigh;
        _fileRecvKey = fileHighToLow;
        _msgSendTag = _kDirLowToHigh;
        _msgRecvTag = _kDirHighToLow;
      } else {
        _msgSendKey = highToLow;
        _msgRecvKey = lowToHigh;
        _fileSendKey = fileHighToLow;
        _fileRecvKey = fileLowToHigh;
        _msgSendTag = _kDirHighToLow;
        _msgRecvTag = _kDirLowToHigh;
      }
      _sasDigits = sas;
      lowToHigh = null;
      highToLow = null;
      fileLowToHigh = null;
      fileHighToLow = null;
    } finally {
      for (final k in [lowToHigh, highToLow, fileLowToHigh, fileHighToLow]) {
        k?.destroy();
      }
      sharedSecret.destroy();
    }
  }
}

// 공개키 비교라 타이밍이 비밀을 흘리진 않지만 프로젝트의 토큰 비교 관례를 핸드셰이크 경계에도 씀
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// 정렬 전용 (같은 길이 32바이트 공개키 가정, 길이가 다르면 짧은 쪽 우선)
int _lexicographicCompare(List<int> a, List<int> b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
