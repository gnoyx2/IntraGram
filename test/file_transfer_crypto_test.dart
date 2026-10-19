import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

import 'support/file_transfer_crypto_pair.dart';

void main() {
  test('round-trips a small single-chunk payload', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(100, (i) => i % 256));

    final wire = await encryptForTest(a, plain);
    final out = await decryptForTest(b, wire, plain.length);

    expect(out, plain);
  });

  test('round-trips a multi-chunk payload larger than one record', () async {
    final (a, b) = await pairSessions();
    // kFileChunkBytes 조각 3개 조금 넘게: 레코드가 여러 개 나오게
    final plain = Uint8List.fromList(
      List<int>.generate(6 * 1024 * 1024 + 777, (i) => i & 0xff),
    );

    final wire = await encryptForTest(a, plain);
    final out = await decryptForTest(b, wire, plain.length);

    expect(out, plain);
  });

  test('an empty stream round-trips to nothing', () async {
    final (a, b) = await pairSessions();
    final wire = await encryptForTest(a, Uint8List(0));
    expect(wire, isEmpty);
    final out = await decryptForTest(b, wire, 0);
    expect(out, isEmpty);
  });

  test('decryptChunks reassembles records regardless of how the transport '
      'chunked the wire bytes (byte-at-a-time)', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(
      List<int>.generate(300 * 1024, (i) => i % 256),
    );

    final wire = await encryptForTest(a, plain);
    // 극단적으로 잘게 쪼개서 먹임: 레코드 경계가 어디든 재조립돼야 함
    final byteAtATime = streamOf([
      for (final byte in wire) [byte],
    ]);
    final out = await decryptChunks(
      byteAtATime,
      b.openBytes,
      transferId: testTransferId,
      attemptId: testAttemptId,
      totalBytes: plain.length,
    ).expand((c) => c).toList();

    expect(out, plain);
  });

  test('a tampered ciphertext byte throws, never silently corrupts', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = await encryptForTest(a, plain);

    // 헤더(4+12+16=32바이트) 뒤 첫 ciphertext 바이트를 뒤집음
    final tampered = List<int>.of(wire);
    tampered[32] = tampered[32] ^ 0xff;

    await expectLater(
      decryptForTest(b, tampered, plain.length),
      throwsA(anything),
    );
  });

  test('an unrelated session cannot open the wire bytes', () async {
    final (a, _) = await pairSessions();
    final (_, c) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = await encryptForTest(a, plain);

    await expectLater(decryptForTest(c, wire, plain.length), throwsA(anything));
  });

  test('reusing a record under a different transferId is rejected', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = await encryptForTest(a, plain, transferId: 'real-transfer');

    // 같은 세션·같은 attemptId지만 다른 transferId로 열려고 함: AAD가
    // 안 맞아서 tag 검증이 실패해야 함(레코드 재사용 방지)
    await expectLater(
      decryptForTest(b, wire, plain.length, transferId: 'other-transfer'),
      throwsA(anything),
    );
  });

  test('reusing a record under a different attemptId is rejected', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = await encryptForTest(a, plain, attemptId: 'attempt-1');

    await expectLater(
      decryptForTest(b, wire, plain.length, attemptId: 'attempt-2'),
      throwsA(anything),
    );
  });

  test('a stream truncated mid-record throws FormatException', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = await encryptForTest(a, plain);

    final truncated = wire.sublist(0, wire.length - 5);
    await expectLater(
      decryptForTest(b, truncated, plain.length),
      throwsA(isA<FormatException>()),
    );
  });

  test('a declared record length outside [28, 28+kFileChunkBytes] is rejected '
      'before buffering the claimed length', () async {
    final (_, b) = await pairSessions();

    Uint8List frameWithLength(int length) {
      final bytes = Uint8List(4);
      ByteData.sublistView(bytes).setUint32(0, length, Endian.big);
      return bytes;
    }

    for (final length in [0, 27, 0xffffffff, 28 + kFileChunkBytes + 1]) {
      await expectLater(
        decryptChunks(
          streamOf([frameWithLength(length)]),
          b.openBytes,
          transferId: testTransferId,
          attemptId: testAttemptId,
          totalBytes: 0,
        ).toList(),
        throwsA(isA<FormatException>()),
        reason: 'length $length must be rejected',
      );
    }
  });

  test(
    'sealBytes/openBytes use a different subkey than the message channel',
    () async {
      final (a, b) = await pairSessions();
      final aad = utf8.encode('t');
      final sealed = await a.sealBytes(Uint8List.fromList([1, 2, 3]), aad: aad);

      // 같은 nonce/cipher/mac을 메시지 채널 open()으로 열려고 하면 실패해야
      // 함: 파일 서브키로 봉인됐지 세션 키로 봉인된 게 아니라서
      await expectLater(
        b.open(
          nonceB64: base64.encode(sealed.nonce),
          cipherB64: base64.encode(sealed.cipher),
          macB64: base64.encode(sealed.mac),
          seq: 0,
        ),
        throwsA(anything),
      );

      // 파일 서브키 openBytes()로는 정상적으로 열림
      final opened = await b.openBytes(
        nonce: sealed.nonce,
        cipher: sealed.cipher,
        mac: sealed.mac,
        aad: aad,
      );
      expect(opened, [1, 2, 3]);
    },
  );
}
