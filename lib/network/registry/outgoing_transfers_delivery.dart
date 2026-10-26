part of 'outgoing_transfers.dart';

extension OutgoingTransfersDelivery on OutgoingTransfers {
  // 수신자 한 명에게 POST로 밀어 넣음. 봉인은 지금 attempt로 함. POST 200은 wire EOF일 뿐이고 완료는 ACK와 같이 봄.
  // 안 던짐: 실패는 그 수신자 상태로만 남김
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
      // 상대는 수락했는데 보낼 곳·토큰이 없음: 그냥 두면 받는 쪽이 0%에 멈춰서 취소로 알림
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
      // 가용 슬롯이 확보될 때까지 대기함 (취소 시 즉시 반환되며 지연 시 kTransferStallTimeout 후 실패 처리됨)
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
      // reader가 닫힌 뒤에 해제하려고 구독이 풀린 때를 잼
      final wire = tracked = _SettledStream(
        _openWireStream(
          source: source,
          transferId: transferId,
          attemptId: attemptId,
          link: link,
          recipient: recipient,
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
      // 취소나 새 시도가 이미 상태를 정리했으면 failed로 안 덮음 (끊긴 토큰 때문에 던진 것뿐)
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

  // 스토어에서 이미 사라진 뒤에도 불려서 store를 다시 안 봄. 도는 전송을 다 끊고 끝나길 기다린 뒤에 source를 버림
  Future<void> discard(String transferId) async {
    final source = _outgoing[transferId];
    var release = _retiring[transferId];
    if (source != null) {
      for (final r in source._recipients.values) {
        r.stopActivity();
      }
      unawaited(source._stopHashing?.call());
      await _drainRecipients(source);
      if (identical(_outgoing[transferId], source)) {
        _outgoing.remove(transferId);
      }
      release = _retireSource(transferId, source);
    }
    if (release == null) return;
    final failure = await release;
    _retiring.remove(transferId);
    // 완료 뒤 소스가 먼저 은퇴했어도 native 실패를 정리 완료로 서명하지 않음.
    if (failure != null) throw TransferCleanupException(failures: [failure]);
  }

  // 사용자가 발신을 취소함: 모든 수신자 작업을 중단하고 각자의 attemptId로 취소를 통보함. 상태는 즉시 cancelled로 전환됨
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

  // 테스트·진단용
  OutgoingFileSource? source(String transferId) => _outgoing[transferId];

  // 링크 연결이 종료됨. recipientKey가 지정된 경우(그룹 방 개별 멤버) 해당 수신자만 실패 처리하고, 없으면(1:1) 대화의 모든 발신을 정리함
  Future<void> handleLinkClosed(
    String conversationId, {
    String? recipientKey,
  }) => _handleLinkClosedOutgoing(this, conversationId, recipientKey);

  Future<void> clear() => _clearOutgoing(this);
}
