part of 'file_streamer.dart';

Future<RandomAccessFile> _openPartial(File file) =>
    file.open(mode: FileMode.write);

// 협상한 크기를 정확히 맞춤: 넘거나 모자라면 멈추고 .part를 지운 뒤 SecurityException을 던짐. 절대 상한은 없고 여유 디스크가 한도임 (LocalSend 방식).
// await for 대신 StreamIterator: 멈춘 스트림에서도 cancel()이 기다리던 moveNext()를 바로 끝냄
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
  void Function(String sha256)? onDigest,
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

  // 취소 때 iterator.cancel()이 끝나길 abort가 기다림 (안 그러면 정리 완료라고 한 뒤에도 구독 취소가 도는 중일 수 있음)
  Future<void>? cancelling;

  // abort가 던진 예외를 아래 catch가 다시 잡아 abort가 중복 실행되는 것을 막음 (두 번 돌면 정리 실패가 두 겹으로 감싸임)
  var aborted = false;

  Future<Never> abort(Object error) async {
    aborted = true;
    // close가 실패해도 삭제는 시도함. 하나라도 실패하면 원래 오류와 함께 TransferCleanupException을 던짐
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
  // 방 직접 전송: 쓰는 대로 해시해서 끝에 offer의 SHA-256과 맞춤 (다시 읽지 않음). 영수증용이면 맞출 값 없이 재기만 함
  final hash = sha256 == null && onDigest == null
      ? null
      : const DartSha256().newHashSink();
  String? digest;
  final unregisterCancel = cancelToken?.onCancel(() {
    final cancel = iterator.cancel();
    // abort가 기다리기 전에 오류로 끝나도 처리 안 된 오류로 안 샘 (await cancelling은 그래도 던짐)
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
      // writeFrom은 쓰기가 끝나야 끝나서 기다리는 동안 다음 청크가 밀림 (배압). IOSink.add는 바로 리턴해서 느린 디스크면 버퍼가 끝없이 쌓였음
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
      digest = base64.encode(hash.hashSync().bytes);
      if (sha256 != null && digest != sha256) {
        await abort(const ContentMismatchException());
      }
    }
    await raf.flush();
    await closeOnce();
    onProgress?.call(meter.total, 0);
    if (digest != null) onDigest?.call(digest);
    return meter.total;
  } on Object catch (e) {
    if (aborted) rethrow;
    await abort(e);
  } finally {
    unregisterCancel?.call();
  }
}
