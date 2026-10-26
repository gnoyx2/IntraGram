part of '../crypto_engine.dart';

extension CryptoSessionMessageRecords on CryptoSession {
  // nonce = 0 4바이트 + 8바이트 BE seq. 방향별 키라 seq만 안 겹치면 nonce도 안 겹침.
  // seq는 AAD로도 인증돼서 바깥 프레임의 평문 seq만 바꿔 다시 보내는 리플레이가 안 통함
  Future<({String nonce, String cipher, String mac})> seal(
    Map<String, dynamic> innerFrame, {
    required int seq,
  }) async {
    final key = _requireSendKey();
    // await 전에 잡음: 범위 밖이거나 이미 쓴 seq 이하면 거부하고, 통과하면 바로 watermark를 올려서 같은 seq 동시 호출도 막힘
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

  // seq를 seal 때와 같은 AAD로 넘겨야 tag가 맞음. 변조·키 불일치·seq 위조·반대 방향 프레임 반사면 던짐
  Future<Map<String, dynamic>> open({
    required String nonceB64,
    required String cipherB64,
    required String macB64,
    required int seq,
  }) async {
    // 파서(EncOuter.seq)가 이미 범위를 거르지만 여기서도 따로 지킴
    if (seq < 0 || seq > kMaxCryptoSequence) {
      throw SecurityException('rejected open: seq $seq out of range');
    }
    final key = _requireRecvKey();
    // 받는 쪽도 nonce = seq를 강제함 (보내는 쪽은 늘 정규 base64라 그냥 비교)
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

// 96비트 nonce 뒤 8바이트에 카운터, 앞 4바이트는 0
Uint8List _nonceFromSeq(int seq) {
  final nonce = Uint8List(12);
  ByteData.sublistView(nonce).setUint64(4, seq, Endian.big);
  return nonce;
}

// [version, direction, seq] 고정 순서 JSON: 양쪽이 같은 바이트를 따로 만들어야 tag가 맞음
List<int> _messageAad(String directionTag, int seq) =>
    utf8.encode(jsonEncode(<dynamic>[kProtocolVersion, directionTag, seq]));
