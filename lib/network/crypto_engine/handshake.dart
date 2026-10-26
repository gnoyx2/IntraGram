part of '../crypto_engine.dart';

const String _kDirLowToHigh = 'l2h';
const String _kDirHighToLow = 'h2l';

extension CryptoSessionHandshake on CryptoSession {
  // 동시 호출은 진행 중인 Future 하나를 같이 기다림. 피어 키가 low-order라 공유 비밀이 0이거나 우리 공개키를 그대로 돌려보내면
  // SecurityException, 키가 깨졌거나 길이가 틀리면 FormatException을 던짐
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

    // 뽑은 키는 성공·실패 상관없이 이 finally가 덮음. 성공하면 필드에 넣고 로컬 참조를 비워서 두 번 안 지움
    SecretKey? lowToHigh;
    SecretKey? highToLow;
    SecretKey? fileLowToHigh;
    SecretKey? fileHighToLow;
    try {
      // 피어가 low-order point를 주면 공유 비밀이 전부 0임 (RFC 7748 §6.1): 거부함
      final sharedBytes = await sharedSecret.extractBytes();
      if (sharedBytes.every((b) => b == 0)) {
        throw SecurityException(
          'rejected handshake: all-zero shared secret (low-order point)',
        );
      }

      // 두 공개키를 정렬해서 HKDF salt로 씀: 모든 키가 이 핸드셰이크 쌍에 묶임. 정렬에서 내가 앞(low)인지로
      // 송수신 방향이 정해져서 따로 주고받을 게 없음
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
        // await 중 링크가 닫힘: 키를 필드에 안 넣어서(finally가 지움) 좀비 세션이 안 생김
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
      // 정렬한 두 임시키를 묶은 세션 지문 (공개값이라 비밀 아님): 조직 자격 PoP가 이 세션에만 통하게 서명에 넣음
      _sessionBinding = Uint8List.fromList(
        const DartSha256().hashSync(<int>[
          ...utf8.encode('intragram/session-binding/v1'),
          ...transcript,
        ]).bytes,
      ).asUnmodifiableView();
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

// 공개키라 타이밍으로 샐 비밀은 없지만 토큰 비교 관례를 그대로 씀
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

int _lexicographicCompare(List<int> a, List<int> b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
