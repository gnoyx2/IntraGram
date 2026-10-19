part of 'file_streamer.dart';

Future<RandomAccessFile> _openPartial(File file) =>
    file.open(mode: FileMode.write);

// FileStreamer.receive 본체. 협상한 크기를 정확히
// 강제: 넘거나 못 채우면 쓰기를 중단하고 부분 파일을 지운 뒤 SecurityException
// 절대 상한은 없고 받는 쪽 여유 디스크로만 제한 (LocalSend와 동일). decrypt가
// 있으면 청킹/크기 강제보다 먼저 복호화 (declaredSize는 평문 기준)
// await for 대신 StreamIterator: 정지된 스트림에서도 cancel()이
// 대기 중인 moveNext()를 즉시 false로 끝내게 함
Future<int> _receive({
  required Stream<List<int>> body,
  required String transferId,
  required String attemptId,
  required String destinationPath,
  required int declaredSize,
  TransferProgress? onProgress,
  OpenChunk? decrypt,
  CancelToken? cancelToken,
  String? sha256,
}) async {
  if (declaredSize < 0) {
    throw SecurityException(
      'refused transfer: declared size $declaredSize is negative',
    );
  }

  final file = File(destinationPath);
  await file.parent.create(recursive: true);
  final raf = await FileStreamer.debugOpenPartial(file);
  final meter = RateMeter();
  var closed = false;

  Future<void> closeOnce() async {
    if (closed) return;
    closed = true;
    await raf.close();
  }

  // cancelToken 취소 시 불리는 iterator.cancel()의 Future(소스 구독 취소 완료)를
  // 붙잡아 abort가 기다림. 안 그러면 moveNext()가 false로 끝나자마자 함수가 끝나서,
  // 호출부(clear)가 "정리 완료"를 선언한 뒤에도 소스 구독 취소가 진행 중일 수 있음
  Future<void>? cancelling;

  // abort가 던진 예외(원래 오류 또는 TransferCleanupException)가
  // 아래 catch에 다시 잡혀 abort가 두 번 돌면
  // 정리 실패가 이중으로 감싸여 보고됨
  var aborted = false;

  Future<Never> abort(Object error) async {
    aborted = true;
    // close 실패가 삭제 시도를 건너뛰게 하지 않음: 둘을 따로 시도하고 하나라도 실패하면
    // 원래 오류와 함께 TransferCleanupException으로 전달
    final failures = <Object>[];
    try {
      await cancelling;
    } on Object catch (e) {
      failures.add(e);
    }
    try {
      await closeOnce();
    } on Object catch (e) {
      failures.add(e);
    }
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      failures.add(e);
    }
    if (failures.isNotEmpty) {
      throw TransferCleanupException(failures: failures, original: error);
    }
    throw error;
  }

  final stallGuarded = body.timeout(kTransferStallTimeout);
  final source = decrypt == null
      ? stallGuarded
      : decryptChunks(
          stallGuarded,
          decrypt,
          transferId: transferId,
          attemptId: attemptId,
          totalBytes: declaredSize,
        );
  final iterator = StreamIterator<List<int>>(
    fixedSizeChunks(source, kFileChunkBytes),
  );
  // 방 직접 전송: 쓰는 대로 해시해서 끝에 offer의 SHA-256과 맞춤 (다시 읽지 않음)
  final hash = sha256 == null ? null : const DartSha256().newHashSink();
  final unregisterCancel = cancelToken?.onCancel(() {
    final cancel = iterator.cancel();
    // abort가 기다리기 전에 에러로 끝나도 "미처리 async 에러"로
    // 안 새게 함 (await cancelling은 여전히 그 에러를 던짐)
    unawaited(cancel.then<void>((_) {}, onError: (Object _) {}));
    cancelling = cancel;
  });

  try {
    while (true) {
      final hasNext = await iterator.moveNext();
      if (cancelToken?.isCancelled ?? false) {
        await abort(const TransferCancelledException());
      }
      if (!hasNext) break;
      final chunk = iterator.current;
      if (meter.total + chunk.length > declaredSize) {
        await abort(
          SecurityException(
            'peer sent more than the ${declaredSize}B it declared',
          ),
        );
      }
      // writeFrom은 실제 쓰기가 끝나야 완료되는 Future라 await for 안에서 기다리면 다음 청크가 자동으로 배압됨
      // (느린 디스크가 스트림 구독을 pause시킴). IOSink.add()는
      // 즉시 리턴해서 디스크가 못 따라가면 청크가 내부 버퍼에 무한정 쌓일 수 있었음
      await raf.writeFrom(chunk);
      hash?.add(chunk);
      meter.add(chunk.length);
      meter.maybeReport(onProgress);
    }
    if (meter.total != declaredSize) {
      await abort(
        SecurityException(
          'peer sent ${meter.total}B but declared exactly '
          '${declaredSize}B (short EOF)',
        ),
      );
    }
    if (hash != null) {
      hash.close();
      if (base64.encode(hash.hashSync().bytes) != sha256) {
        await abort(const ContentMismatchException());
      }
    }
    await raf.flush();
    await closeOnce();
    onProgress?.call(meter.total, 0);
    return meter.total;
  } on Object catch (e) {
    if (aborted) rethrow;
    await abort(e);
  } finally {
    unregisterCancel?.call();
  }
}
