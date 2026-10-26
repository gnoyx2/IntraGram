part of 'outgoing_transfers.dart';

extension OutgoingTransfersPullBody on OutgoingTransfers {
  // GET 응답 body: wire를 흘리고 수명을 여기서 다 관리함. 끝까지 가면 EOF, 끊기거나 오류면 실패.
  // 어떻게 끝나든 게이트 슬롯과 active는 한 번만 돌려줌 (아무도 안 받아 가도 워치독이 정리). 취소되면 오류로 끊음
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

    // upstreamCancel이 있으면 reader가 닫힌 뒤에 done을 풂 (정리하는 쪽이 그 전에 네이티브 자원을 놓지 않게)
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
