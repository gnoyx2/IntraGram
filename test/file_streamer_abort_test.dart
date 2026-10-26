import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

import 'support/chmod_injection.dart';
import 'support/file_transfer_crypto_pair.dart';

// FileStreamer.receive가 어떤 이유로 중단돼도(크기 초과, 짧은 EOF,
// 취소, 복호화 실패, handle close 실패, 삭제 실패) 앱이 소유한 .part를
// 끝까지 지우거나 실패를 드러내고, 정지한 소스 앞의 취소가 stall timeout(25s) 없이 곧바로 끝나는지

// 진짜 handle을 감싸되 close()가 끝난 직후 afterClose를 돌리는
// handle: FileStreamer.debugOpenPartial에 끼워
// close 실패/삭제 실패를 결정적으로 만듦 (abort는 close를 먼저 하고 삭제를 나중에 함)
class _HookedFile implements RandomAccessFile {
  _HookedFile(this._inner, this._afterClose);
  final RandomAccessFile _inner;
  final void Function() _afterClose;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    await _inner.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await _inner.flush();
    return this;
  }

  @override
  Future<void> close() async {
    await _inner.close();
    _afterClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late String dest;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_streamer_abort_');
    dest = '${dir.path}/in.part';
  });
  tearDown(() {
    FileStreamer.debugOpenPartial = (file) => file.open(mode: FileMode.write);
    Process.runSync('chmod', ['755', dir.path]);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<int> receive(
    Stream<List<int>> body, {
    int size = 8,
    CancelToken? cancelToken,
    OpenChunk? decrypt,
  }) => FileStreamer.receive(
    body: body,
    transferId: testTransferId,
    attemptId: testAttemptId,
    destinationPath: dest,
    declaredSize: size,
    cancelToken: cancelToken,
    decrypt: decrypt,
  );

  Future<Object?> outcomeOf(Future<int> future) =>
      future.then<Object?>((_) => null, onError: (Object e) => e);

  test(
    'a body larger than declared is rejected and its part removed',
    () async {
      await expectLater(
        receive(Stream.value(List<int>.filled(9, 1))),
        throwsA(isA<SecurityException>()),
      );
      expect(File(dest).existsSync(), isFalse);
    },
  );

  test('a short EOF is rejected and its part removed', () async {
    await expectLater(
      receive(Stream.value(const [1, 2, 3])),
      throwsA(isA<SecurityException>()),
    );
    expect(File(dest).existsSync(), isFalse);
  });

  test('a tampered encrypted record fails and its part is removed', () async {
    final (a, b) = await pairSessions();
    final plain = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final wire = await encryptForTest(a, plain);
    wire[wire.length - 1] ^= 0xff; // 마지막 tag/cipher 바이트 변조

    await expectLater(
      receive(Stream.value(wire), size: 64, decrypt: b.openBytes),
      throwsA(anything),
    );
    expect(File(dest).existsSync(), isFalse);
  });

  for (final encrypted in [false, true]) {
    test('cancel on a stalled ${encrypted ? 'encrypted' : 'plain'} body '
        'returns promptly and leaves no part', () async {
      final (_, b) = await pairSessions();
      final body = StreamController<List<int>>(
        onCancel: () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final token = CancelToken();
      final outcome = outcomeOf(
        receive(
          body.stream,
          cancelToken: token,
          decrypt: encrypted ? b.openBytes : null,
        ),
      );
      await pumpEventQueue(times: 30);

      final watch = Stopwatch()..start();
      token.cancel();
      expect(await outcome, isA<TransferCancelledException>());

      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(File(dest).existsSync(), isFalse);
    });
  }

  test('a failing handle close never skips the delete', () async {
    FileStreamer.debugOpenPartial = (file) async => _HookedFile(
      await file.open(mode: FileMode.write),
      () => throw const FileSystemException('injected close failure'),
    );

    final error = await outcomeOf(
      receive(Stream.value(List<int>.filled(9, 1))),
    );

    expect(error, isA<TransferCleanupException>());
    final cleanup = error! as TransferCleanupException;
    expect(cleanup.original, isA<SecurityException>());
    expect(cleanup.failures, hasLength(1), reason: 'the close failure only');
    expect(File(dest).existsSync(), isFalse, reason: 'delete still ran');
  });

  test(
    'a part that cannot be deleted is reported, not hidden',
    () async {
      FileStreamer.debugOpenPartial = (file) async => _HookedFile(
        await file.open(mode: FileMode.write),
        () => Process.runSync('chmod', ['555', dir.path]), // close 뒤 삭제 불가
      );

      final error = await outcomeOf(
        receive(Stream.value(List<int>.filled(9, 1))),
      );

      expect(error, isA<TransferCleanupException>());
      final cleanup = error! as TransferCleanupException;
      expect(cleanup.original, isA<SecurityException>());
      expect(cleanup.failures.single, isA<FileSystemException>());
      expect(File(dest).existsSync(), isTrue, reason: 'still there, reported');
    },
    skip: chmodInjectionSkip,
  );
}
