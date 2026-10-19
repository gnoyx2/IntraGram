part of '../crypto_engine.dart';

extension CryptoSessionMessageRecords on CryptoSession {
  // nonce = 4바이트 0 + 8바이트 BE seq. 방향별 키가 이미 유일해서 seq가 안 겹치면 nonce도 안 겹침
  // (호출부가 단일 직렬 큐에서 배정, PeerLinkOutbound 참고). seq는 AEAD associated data로도 인증돼서
  // outer 프레임의 평문 seq만 위조해 재전송하는 리플레이를 막음
  Future<({String nonce, String cipher, String mac})> seal(
    Map<String, dynamic> innerFrame, {
    required int seq,
  }) async {
    final key = _requireSendKey();
    // await 전에 예약: 범위 밖이거나 이미 쓴 seq 이하면 거부함 (호출부가 순서를 지켜도 세션이 (key, nonce)
    // 재사용을 한 번 더 막음). 통과하면 즉시 watermark를 올려서 같은 seq의 동시 호출도 여기서 막힘
    if (seq < 0 || seq > kMaxCryptoSequence || seq <= _lastSealedSeq) {
      throw SecurityException(
        'rejected seal: seq $seq out of order or out of range',
      );
    }
    _lastSealedSeq = seq;
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(innerFrame)));
    try {
      final box = await _engine._aead.encrypt(
        plaintext,
        secretKey: key,
        nonce: _nonceFromSeq(seq),
        aad: _messageAad(_msgSendTag!, seq),
      );
      return (
        nonce: base64.encode(box.nonce),
        cipher: base64.encode(box.cipherText),
        mac: base64.encode(box.mac.bytes),
      );
    } finally {
      SecureBytes.wipe(plaintext);
    }
  }

  // seq는 seal과 같은 associated data로 다시 넘겨야 tag가 검증됨
  // tag가 틀리면(변조/키 불일치/seq 위조/반대 방향 키로 봉인된 프레임의 반사) 던짐
  Future<Map<String, dynamic>> open({
    required String nonceB64,
    required String cipherB64,
    required String macB64,
    required int seq,
  }) async {
    // 파싱 경계(EncOuter.seq)가 이미 0..max로 제한하지만 이
    // 메서드도 독립적으로 같은 경계를 지킴 (호출부가 바뀌어도 한 번 더 막힘)
    if (seq < 0 || seq > kMaxCryptoSequence) {
      throw SecurityException('rejected open: seq $seq out of range');
    }
    final key = _requireRecvKey();
    // nonce = seq 불변식을 받는 쪽에서도 강제함: wire n이 seq로 계산한 값과 다르면 버림
    // (nonce는 공개값이라 일반 비교로 충분, 보내는 쪽은 늘 정규 base64)
    final nonce = _nonceFromSeq(seq);
    if (nonceB64 != base64.encode(nonce)) {
      throw SecurityException('rejected open: nonce does not match seq $seq');
    }
    final box = SecretBox(
      base64.decode(cipherB64),
      nonce: nonce,
      mac: Mac(base64.decode(macB64)),
    );
    final plaintext = await _engine._aead.decrypt(
      box,
      secretKey: key,
      aad: _messageAad(_msgRecvTag!, seq),
    );
    try {
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('decrypted frame is not a JSON object');
      }
      return decoded;
    } finally {
      SecureBytes.wipe(plaintext);
    }
  }
}

// 96비트 ChaCha20 nonce 중 뒤 8바이트에 카운터만 넣고 앞은 0 (seq가 2^63을 넘을 일이 없어 여유분)
Uint8List _nonceFromSeq(int seq) {
  final nonce = Uint8List(12);
  ByteData.sublistView(nonce).setUint64(4, seq, Endian.big);
  return nonce;
}

// [version, direction, seq] 고정 순서 JSON 배열:
// 모든 수신자가 같은 바이트를 독립적으로 재구성할 수 있어야 tag가 맞음
List<int> _messageAad(String directionTag, int seq) =>
    utf8.encode(jsonEncode(<dynamic>[kProtocolVersion, directionTag, seq]));
