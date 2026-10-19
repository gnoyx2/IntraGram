part of '../crypto_engine.dart';

// 메시지 채널과 별도 키 + 독립 카운터. AAD는 호출부(file_transfer_crypto.dart)가
// transferId/attemptId/
// chunkIndex/totalBytes로 만들어 넘기고, 이 파일은 그 바이트를 그대로 AEAD에 전달할 뿐 내용을 모름
extension CryptoSessionFileRecords on CryptoSession {
  // base64를 안 거침 (벌크 바이너리에 33% 부풀리는 건 낭비). nonce/cipher/mac을 raw 바이트로 리턴
  Future<({Uint8List nonce, Uint8List cipher, Uint8List mac})> sealBytes(
    Uint8List plaintext, {
    required Uint8List aad,
  }) async {
    final key = _requireFileSendKey();
    // 증가 전에 상한 검사: 2^53개 청크는 사실상 불가능하지만 닿기 직전에 던져서 nonce가 감겨
    // 같은 키로 재사용되는 걸 원천 차단함. 호출부는 다른 seal 실패와 똑같이 전송 실패로 처리
    if (_fileSendCounter >= kMaxCryptoSequence) {
      throw SecurityException(
        'rejected sealBytes: file crypto sequence exhausted',
      );
    }
    // await 전에 카운터를 예약해서 동시에 여러 청크를 seal해도 같은 seq를 두 번 안 씀
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

  // tag가 틀리면(변조/키 불일치/다른 전송·attempt·청크 순번의 AAD) 던짐
  // 쓰레기를 파일 바이트인 척 디스크에 흘리지 않게 함
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
    // 반환값은 새 복사본이라 원본 decrypt 버퍼(패키지 내부 표현)는 호출부에 안 넘어가고 여기서 바로 wipe함
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
