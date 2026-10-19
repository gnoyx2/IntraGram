part of 'outgoing_transfers.dart';

extension OutgoingTransfersDelivery on OutgoingTransfers {
  // 수신자 한 명에게 HTTP로 바이트를 스트리밍 (앱-앱 push). 봉인은 offer 시점이 아니라
  // 지금 그 수신자의 현재 attemptId로 해서 재시도가 새 attemptId를 발급해도 따라감
  // 성공하면 POST 200을 그 attempt의 wire EOF로 기록 (complete는 ACK와
  // 결합해서 판정, _onWireEof). 절대 안 던짐: 실패는 그 수신자의 상태로만 기록
  Future<void> _runPush(
    String transferId,
    OutgoingFileSource source,
    _OutgoingRecipient recipient,
  ) async {
    final attemptId = recipient.attemptId;
    final host = source.host;
    final port = source.port;
    final pushToken = recipient.pushToken;
    if (host == null || port == null || pushToken == null) {
      // 피어는 accept를 보냈는데 보낼 곳/토큰이 없음: 조용히 무시하면 받는 쪽 진행률이 0%에서 영원히 멈추니
      // cancel로 알려서 받는 쪽이 실패를 보고 재시도할 수 있게 함
      unawaited(
        _linkForRecipient(
          source,
          recipient,
        )?.sendFileCancel(transferId, attemptId: attemptId),
      );
      recipient
        ..error = 'network'
        ..phase = _RecipientPhase.failed;
      _syncTransfer(transferId);
      return;
    }

    final cancelToken = CancelToken();
    recipient.cancelToken = cancelToken;
    var acquired = false;
    _SettledStream? tracked;
    try {
      // 동시 전송 상한: 자리 날 때까지 기다림 (그동안 취소가 대기열에서도 즉시 빠지게 cancelToken도 같이 줌)
      // 무한정은 안 기다리고 막혀도 kTransferStallTimeout 뒤엔 실패로 드러남
      await gate.acquire(
        timeout: kTransferStallTimeout,
        cancelToken: cancelToken,
      );
      acquired = true;
      if (cancelToken.isCancelled || recipient.attemptId != attemptId) return;
      recipient
        ..tokenConsumed = true
        ..phase = _RecipientPhase.transferring;
      final link =
          _linkForRecipient(source, recipient) ??
          _linkFor(source.conversationId);
      // 소스 구독이 완전히 풀린 시점을 알아야 reader를 닫은 뒤에 release할 수 있음
      final wire = tracked = _SettledStream(
        _openWireStream(
          source: source,
          transferId: transferId,
          attemptId: attemptId,
          link: link,
        ),
      );
      _syncTransfer(transferId);
      await FileStreamer.send(
        host: host,
        port: port,
        transferId: transferId,
        attemptId: attemptId,
        authToken: pushToken,
        fileName: source.name,
        totalBytes: source.size,
        wireBytes: _wireBytesOf(source),
        bytes: wire.stream,
        onProgress: (sent, bps) => store.updateTransfer(
          transferId,
          (t) => t.copyWith(transferredBytes: sent, bytesPerSecond: bps),
        ),
        cancelToken: cancelToken,
      );
      if (recipient.attemptId != attemptId || recipient.isTerminal) return;
      _onWireEof(transferId, source, recipient);
    } on Object catch (e) {
      // 사용자 취소/상대 취소/새 시도가 이미 상태를 정리했으면 failed로
      // 덮어쓰지 않음: 이 catch는 끊긴 토큰 때문에 I/O가 던진 게 전파된
      // 것뿐
      if (recipient.attemptId == attemptId && !recipient.isTerminal) {
        recipient
          ..error = classifyTransferError(e)
          ..phase = _RecipientPhase.failed;
        _syncTransfer(transferId);
      }
    } finally {
      if (identical(recipient.cancelToken, cancelToken)) {
        recipient.cancelToken = null;
      }
      if (acquired) gate.release();
      // 이 작업(active)이 끝났다고 알리기 전에 소스 reader까지 닫히길 기다림
      await tracked?.settled;
    }
  }

  // 스토어에서 transferId가 이미 사라진 뒤(소각/전체 와이프) 불림: 진행 중 전송을 전부 끊고 끝날 때까지 기다린 뒤에만
  // source를 버림. cancelTransfer와 달리
  // store.transfer를 다시 조회하지 않음 (이미 없어서 가드가 항상 실패)
  Future<void> discard(String transferId) async {
    final source = _outgoing[transferId];
    if (source == null) return;
    for (final r in source._recipients.values) {
      r.stopActivity();
    }
    unawaited(source._stopHashing?.call());
    await _drainRecipients(source);
    if (identical(_outgoing[transferId], source)) _outgoing.remove(transferId);
    await _releaseSource(source); // reader가 다 닫힌 뒤 native 자원을 놓음
  }

  // 아직 안 보내졌거나(offered) 전송 중인 아웃고잉 전송을 사용자가
  // 무름: 모든 수신자를 끊고 각자에게 자기 attempt로 취소를 알림
  // 상태는 응답성 우선으로 즉시 cancelled로 세팅 (실제 소켓 정리는
  // 비동기로 뒤따라도 push의 catch가 failed로 덮어쓰지 않음)
  void cancelTransfer(String transferId) {
    final transfer = store.transfer(transferId);
    if (transfer == null || transfer.direction != TransferDirection.outgoing) {
      return;
    }
    if (transfer.state != TransferState.offered &&
        transfer.state != TransferState.transferring) {
      return;
    }
    final source = _outgoing[transferId];
    if (source != null) {
      unawaited(source._stopHashing?.call());
      for (final r in source._recipients.values) {
        if (r.isTerminal) continue;
        r.stopActivity();
        r.phase = _RecipientPhase.cancelled;
        unawaited(
          _linkForRecipient(
            source,
            r,
          )?.sendFileCancel(transferId, attemptId: r.attemptId),
        );
      }
    }
    store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.cancelled),
    );
    if (source != null) _removeSource(transferId);
  }

  Future<void> retryTransfer(String transferId) =>
      _retryOutgoingTransfer(this, transferId);

  // 테스트/진단용 staged source 조회
  OutgoingFileSource? source(String transferId) => _outgoing[transferId];

  // 링크가 닫힘. recipientKey가 주어지면(그룹 방의 멤버 링크 하나)
  // 그 수신자만 실패로 돌리고 나머지 수신자의 source와 상태는 그대로 둠
  // 없으면(1:1 링크) 그 대화의 전송 전부를 버림
  Future<void> handleLinkClosed(
    String conversationId, {
    String? recipientKey,
  }) => _handleLinkClosedOutgoing(this, conversationId, recipientKey);

  Future<void> clear() => _clearOutgoing(this);
}
