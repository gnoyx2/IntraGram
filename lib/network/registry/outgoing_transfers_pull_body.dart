part of 'outgoing_transfers.dart';

extension OutgoingTransfersPullBody on OutgoingTransfers {
  // GET 응답 body: wire 데이터를 송출하고 전체 수명주기를 관리함. 정상 종료 시 EOF, 중단이나 오류 발생 시 실패 처리함.
  // 종료 사유와 무관하게 게이트 슬롯과 active 상태는 단 1회 반환됨 (미수신 시 워치독이 정리함). 취소 시 예외를 전달하며 중단함
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

    // upstreamCancel이 있으면 reader가 종료된 후에 done을 완료함 (정리 작업 쪽에서 사전에 네이티브 자원을 해제하지 않게 막음)
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
