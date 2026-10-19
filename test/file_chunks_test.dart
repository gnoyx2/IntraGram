import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/file_chunks.dart';

// fixedSizeChunks: 고정 크기 재분할, 그리고 취소/pause가
// async*처럼 await에 안 막히고 소스 구독까지 바로 전달됨

Future<List<List<int>>> _chunks(List<List<int>> parts, int size) async {
  final out = await fixedSizeChunks(Stream.fromIterable(parts), size).toList();
  return out.map((c) => c.toList()).toList();
}

void main() {
  test(
    're-cuts arbitrary parts into fixed chunks with a smaller tail',
    () async {
      expect(
        await _chunks([
          [1, 2],
          [3],
          [4, 5, 6, 7, 8],
          [9],
        ], 4),
        [
          [1, 2, 3, 4],
          [5, 6, 7, 8],
          [9],
        ],
      );
    },
  );

  test('an exact multiple leaves no empty tail chunk', () async {
    expect(
      await _chunks([
        [1, 2, 3, 4, 5, 6],
      ], 3),
      [
        [1, 2, 3],
        [4, 5, 6],
      ],
    );
  });

  test('empty parts and an empty stream produce nothing', () async {
    expect(await _chunks(const [], 4), isEmpty);
    expect(await _chunks([const [], const []], 4), isEmpty);
  });

  test('one huge part is split into full chunks plus a remainder', () async {
    final out = await _chunks([List<int>.generate(11, (i) => i)], 4);
    expect(out.map((c) => c.length), [4, 4, 3]);
    expect(out.expand((c) => c), List<int>.generate(11, (i) => i));
  });

  test('emitted chunks are copies, not views of the reused buffer', () async {
    final out = await fixedSizeChunks(
      Stream.fromIterable([
        [1, 2],
        [3, 4],
        [5, 6],
      ]),
      2,
    ).toList();
    expect(out.map((c) => c.toList()), [
      [1, 2],
      [3, 4],
      [5, 6],
    ]);
  });

  test('accepts a Stream<Uint8List> source, as dart:io bodies are', () async {
    // 런타임 타입이 Stream<Uint8List>인 소스를 정적 타입 Stream<List<int>>로
    // 넘기면 예전 구현은 transform에서 런타임 캐스트 오류가 났음
    final source = Stream<Uint8List>.fromIterable([
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5]),
    ]);
    final out = await fixedSizeChunks(source, 2).toList();
    expect(out.map((c) => c.toList()), [
      [1, 2],
      [3, 4],
      [5],
    ]);
  });

  test('a source error is forwarded to the consumer', () async {
    final source = StreamController<List<int>>();
    final result = fixedSizeChunks(source.stream, 4).toList();
    source
      ..add([1, 2])
      ..addError(StateError('boom'));
    await expectLater(result, throwsStateError);
    unawaited(source.close());
  });

  test('cancel reaches a silent source at once and completes', () async {
    var sourceCancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () => sourceCancelled = true,
    );
    final iterator = StreamIterator<List<int>>(
      fixedSizeChunks(source.stream, 4),
    );
    final pending = iterator.moveNext();
    await pumpEventQueue();

    final watch = Stopwatch()..start();
    await iterator.cancel();

    expect(await pending, isFalse);
    expect(sourceCancelled, isTrue, reason: 'the source subscription ended');
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 500)));
  });

  test('pausing the consumer pauses the source (backpressure)', () async {
    final source = StreamController<List<int>>();
    final subscription = fixedSizeChunks(source.stream, 4).listen((_) {});
    await pumpEventQueue();

    subscription.pause();
    await pumpEventQueue();
    expect(source.isPaused, isTrue);

    subscription.resume();
    await pumpEventQueue();
    expect(source.isPaused, isFalse);
    await subscription.cancel();
  });
}
