part of '../crypto_engine.dart';

// 메시지와 다른 키·카운터. AAD는 호출부(file_transfer_crypto.dart)가 전송·시도·청크 번호·전체 크기로 만들어 넘김
extension CryptoSessionFileRecords on CryptoSession {
  // 벌크라 base64 안 거치고 raw 바이트로 돌려줌
  Future<({Uint8List nonce, Uint8List cipher, Uint8List mac})> sealBytes(
    Uint8List plaintext, {
    required Uint8List aad,
  }) async {
    final key = _requireFileSendKey();
    // 올리기 전에 상한 검사: 2^53 청크는 사실상 불가능해도 닿기 전에 던져서 nonce가 감기는 일은 원천 차단
    if (_fileSendCounter >= kMaxCryptoSequence) {
      throw SecurityException(
        'rejected sealBytes: file crypto sequence exhausted',
      );
    }
    // await 전에 카운터를 잡아서 여러 청크를 동시에 seal해도 seq가 안 겹침
    final seq = _fileSendCounter++;
    final box = await _engine._aead.encrypt(
      plaintext,
      secretKey: key,
      nonce: _nonceFromSeq(seq),
      aad: aad,
    );
    return (
      nonce: Uint8List.fromList(box.nonce),
      cipher: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  // tag가 틀리면(변조, 키 불일치, 다른 전송·시도·청크의 AAD) 던짐: 쓰레기가 파일 바이트인 척 디스크에 안 감
  Future<Uint8List> openBytes({
    required Uint8List nonce,
    required Uint8List cipher,
    required Uint8List mac,
    required Uint8List aad,
  }) async {
    final key = _requireFileRecvKey();
    final box = SecretBox(cipher, nonce: nonce, mac: Mac(mac));
    final plaintext = await _engine._aead.decrypt(
      box,
      secretKey: key,
      aad: aad,
    );
    // 패키지 내부 버퍼는 안 넘기고 사본을 준 뒤 바로 지움
    try {
      return Uint8List.fromList(plaintext);
    } finally {
      SecureBytes.wipe(plaintext);
    }
  }

  SecretKey _requireFileSendKey() {
    final key = _fileSendKey;
    if (key == null || _destroyed) {
      throw StateError('CryptoSession used before handshake / after destroy');
    }
    return key;
  }

  SecretKey _requireFileRecvKey() {
    final key = _fileRecvKey;
    if (key == null || _destroyed) {
      throw StateError('CryptoSession used before handshake / after destroy');
    }
    return key;
  }
}
