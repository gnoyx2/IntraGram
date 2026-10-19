part of 'outgoing_transfers.dart';

extension OutgoingTransfersPullBody on OutgoingTransfers {
  // GET 응답 body: wire를 그대로 흘리되 수명을 여기서 전부 관리함. 끝까지 흘렀으면
  // wire EOF로 기록(_onWireEof), 중간에 구독이 취소되거나 오류가 나면 실패로
  // 기록
  // 어떤 경로로 끝나든 게이트 슬롯/active 작업을 정확히 한 번 돌려줌 (구독이 아예 안 시작돼도
  // 워치독이 정리). cancelToken이 취소되면(사용자 취소/패닉) 스트림을 오류로 끊음
  Stream<List<int>> _pullBody({
    required String transferId,
    required OutgoingFileSource source,
    required _OutgoingRecipient recipient,
    required String attemptId,
    required Stream<List<int>> wire,
    required CancelToken cancelToken,
    required Completer<void> done,
  }) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;
    Timer? watchdog;
    void Function()? unregisterCancel;
    var closed = false;
    final meter = RateMeter();

    void completeDone() {
      if (identical(recipient.active, done.future)) recipient.active = null;
      if (!done.isCompleted) done.complete();
    }

    // upstreamCancel이 있으면 소스 구독의 취소(= reader close)가 끝난 뒤에 done/active를 풀어줌:
    // 정리하는 쪽(_removeSource/discard)이 reader가 닫히기 전에 native 자원을 release하지 않게
    void finish({required bool eof, Future<void>? upstreamCancel}) {
      if (closed) return;
      closed = true;
      watchdog?.cancel();
      unregisterCancel?.call();
      gate.release();
      if (recipient.attemptId == attemptId) {
        if (identical(recipient.cancelToken, cancelToken)) {
          recipient.cancelToken = null;
        }
        if (eof) {
          _onWireEof(transferId, source, recipient);
        } else if (recipient.phase == _RecipientPhase.transferring) {
          recipient
            ..error = 'network'
            ..phase = _RecipientPhase.failed;
          _syncTransfer(transferId);
        }
      }
      if (upstreamCancel == null) {
        completeDone();
        return;
      }
      unawaited(
        upstreamCancel
            .timeout(kTransferStallTimeout, onTimeout: () {})
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(completeDone),
      );
    }

    controller = StreamController<List<int>>(
      onListen: () {
        watchdog?.cancel();
        sub = wire.listen(
          (chunk) {
            meter.add(chunk.length);
            meter.maybeReport(
              (sent, bps) => store.updateTransfer(
                transferId,
                (t) => t.copyWith(transferredBytes: sent, bytesPerSecond: bps),
              ),
            );
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            finish(eof: false);
            controller.addError(error, stack);
            unawaited(controller.close());
          },
          onDone: () {
            finish(eof: true);
            unawaited(controller.close());
          },
          cancelOnError: true,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () async {
        await sub?.cancel();
        finish(eof: false);
      },
    );
    unregisterCancel = cancelToken.onCancel(() {
      if (closed) return;
      finish(eof: false, upstreamCancel: sub?.cancel());
      controller.addError(const TransferCancelledException());
      unawaited(controller.close());
    });
    watchdog = Timer(kTransferStallTimeout, () {
      if (closed) return;
      finish(eof: false, upstreamCancel: sub?.cancel());
      unawaited(controller.close());
    });
    return controller.stream;
  }
}
