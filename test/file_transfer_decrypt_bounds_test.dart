import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

import 'support/file_transfer_crypto_pair.dart';

// decryptChunks가 레코드 하나 크기의 고정 버퍼로 wire를 재조립하면서 길이/개수/EOF를 본문을 버퍼링하기 전에 강제하고,
// 실패 뒤엔 평문을 더 안 내보내며, 취소가 정지한 wire 앞에서도 곧바로 끝나는지 검증함

Uint8List _prefix(int length) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, length, Endian.big);
  return bytes;
}

// 스트림이 흘러오는 대로 데이터/에러 이벤트를 모아 done까지 기다릴 수 있게 함
class _Collected {
  final data = <List<int>>[];
  final errors = <Object>[];
  final done = Completer<void>();
}

_Collected _collect(Stream<List<int>> stream) {
  final out = _Collected();
  stream.listen(
    out.data.add,
    onError: out.errors.add,
    onDone: out.done.complete,
  );
  return out;
}

void main() {
  late CryptoSession sender;
  late CryptoSession receiver;
  setUp(() async {
    (sender, receiver) = await pairSessions();
  });

  Stream<List<int>> decrypt(Stream<List<int>> wire, int totalBytes) =>
      decryptChunks(
        wire,
        receiver.openBytes,
        transferId: testTransferId,
        attemptId: testAttemptId,
        totalBytes: totalBytes,
      );

  test(
    'accepts a Stream<Uint8List> wire, as dart:io request bodies are',
    () async {
      final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
      final wire = Uint8List.fromList(await encryptForTest(sender, plain));

      final out = await decrypt(Stream<Uint8List>.value(wire), 50).toList();

      expect(out.expand((c) => c), plain);
    },
  );

  test('a record of the wrong size for its position is rejected as soon as '
      'its length prefix arrives, before any body', () async {
    final wire = StreamController<List<int>>();
    final result = decrypt(wire.stream, 100).toList();

    // 100바이트 파일의 유일한 레코드는 정확히 28+100바이트여야 함: 본문이 오기
    // 전에 (접두 4바이트만으로) 거부돼야 하니 wire를 닫지도 않음
    wire.add(_prefix(28 + 99));

    await expectLater(result, throwsA(isA<FormatException>()));
    unawaited(wire.close());
  });

  test('a full-size record where a short tail is expected is rejected at '
      'its prefix', () async {
    final wire = StreamController<List<int>>();
    final result = decrypt(wire.stream, 10).toList();

    wire.add(_prefix(28 + kFileChunkBytes));

    await expectLater(result, throwsA(isA<FormatException>()));
    unawaited(wire.close());
  });

  test('an extra record is rejected at its length prefix, after the valid '
      'one is delivered', () async {
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = StreamController<List<int>>();
    final collected = _collect(decrypt(wire.stream, 50));

    wire
      ..add(await encryptForTest(sender, plain))
      ..add(_prefix(60)); // 두 번째(여분) 레코드의 접두: 본문은 안 옴
    await pumpEventQueue(times: 50);
    unawaited(wire.close());
    await collected.done.future;

    expect(collected.data.expand((c) => c), plain);
    expect(collected.errors.single, isA<FormatException>());
    expect(
      (collected.errors.single as FormatException).message,
      contains('extra record'),
    );
  });

  test('once a record is rejected the rest of the wire is dropped, not '
      'parsed again', () async {
    final wire = StreamController<List<int>>();
    final collected = _collect(decrypt(wire.stream, 10));

    wire
      ..add(_prefix(28 + kFileChunkBytes)) // 잘못된 크기 → 거부
      ..add(Uint8List(64 * 1024)); // 그 뒤 이어지는 바이트: 다시 파싱하면 안 됨
    await pumpEventQueue(times: 50);
    unawaited(wire.close());
    await collected.done.future.timeout(const Duration(seconds: 5));

    expect(collected.errors, hasLength(1));
    expect(collected.data, isEmpty);
  });

  test('after one bad record no plaintext is emitted, even if later '
      'records are valid', () async {
    const total = 2 * kFileChunkBytes + 10; // 레코드 3개
    final wire = await encryptForTest(sender, Uint8List(total));
    wire[4 + 12 + 16 + 5] ^= 0xff; // 첫 레코드 ciphertext 변조: 나머지 둘은 멀쩡함

    final collected = _collect(decrypt(Stream.value(wire), total));
    await collected.done.future;

    expect(collected.data, isEmpty, reason: 'no plaintext after a failure');
    expect(collected.errors, isNotEmpty);
  });

  test('stray trailing bytes after the last record are a malformed '
      'transfer', () async {
    final plain = Uint8List.fromList(List<int>.generate(50, (i) => i));
    final wire = [...await encryptForTest(sender, plain), 0, 0];

    final collected = _collect(decrypt(Stream.value(wire), 50));
    await collected.done.future;

    expect(collected.errors.single, isA<FormatException>());
    expect(
      (collected.errors.single as FormatException).message,
      contains('mid-record'),
    );
  });

  test('a stream that ends between records is a truncated transfer', () async {
    const total = kFileChunkBytes + 10; // 레코드 2개
    final wire = await encryptForTest(sender, Uint8List(total));
    final firstRecord = 4 + 28 + kFileChunkBytes;

    final collected = _collect(
      decrypt(Stream.value(wire.sublist(0, firstRecord)), total),
    );
    await collected.done.future;

    expect(collected.errors.single, isA<FormatException>());
    expect(
      (collected.errors.single as FormatException).message,
      contains('1 of 2'),
    );
  });

  test('cancelling reaches a silent wire at once and completes', () async {
    var wireCancelled = false;
    final wire = StreamController<List<int>>(
      onCancel: () => wireCancelled = true,
    );
    final iterator = StreamIterator<List<int>>(decrypt(wire.stream, 100));
    final pending = iterator.moveNext();
    await pumpEventQueue();

    final watch = Stopwatch()..start();
    await iterator.cancel();

    expect(await pending, isFalse);
    expect(wireCancelled, isTrue, reason: 'the wire subscription ended');
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });
}
