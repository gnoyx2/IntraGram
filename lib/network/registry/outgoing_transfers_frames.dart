part of 'outgoing_transfers.dart';

// 내 보내기에 대한 상대 제어 프레임. (전송 id, attempt, 인증된 발신자)가 그 수신자의 지금 attempt와 안 맞으면 아무것도 안 건드림 (타이머 포함)
extension OutgoingTransfersFrames on OutgoingTransfers {
  // push면 밀기 시작하고 pull이면 수락만 적음 (데이터는 그 수신자가 GET으로 당김)
  void handleAccepted(
    String transferId, {
    required String attemptId,
    required String pushToken,
    required String actorKey,
  }) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final recipient = _recipientFor(source, actorKey);
    if (recipient == null || recipient.attemptId != attemptId) return;
    if (recipient.phase != _RecipientPhase.offered) return;
    recipient.phase = _RecipientPhase.accepted;
    if (source.mode == FileTransferMode.pull) {
      _syncTransfer(transferId);
      return;
    }
    recipient.pushToken = pushToken;
    final running = _runPush(transferId, source, recipient);
    recipient.active = running;
    unawaited(
      running.whenComplete(() {
        if (identical(recipient.active, running)) recipient.active = null;
      }),
    );
    _syncTransfer(transferId);
  }

  // 해당 수신자만 rejected 상태로 전환함 (모든 수신자 종료 시 _syncTransfer가 source를 정리함)
  void handleRejected(
    String transferId, {
    required String attemptId,
    required String actorKey,
  }) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final recipient = _recipientFor(source, actorKey);
    if (recipient == null || recipient.attemptId != attemptId) return;
    if (recipient.isTerminal) return;
    recipient.stopActivity();
    recipient.phase = _RecipientPhase.rejected;
    _syncTransfer(transferId);
  }

  // 피어 측에서 취소함: 해당 수신자만 cancelled 상태로 전환함 (피어에게 재통보하지 않음)
  void handleCancelledByPeer(
    String transferId, {
    required String attemptId,
    required String actorKey,
  }) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final recipient = _recipientFor(source, actorKey);
    if (recipient == null || recipient.attemptId != attemptId) return;
    if (recipient.isTerminal) return;
    recipient.stopActivity();
    recipient.phase = _RecipientPhase.cancelled;
    _syncTransfer(transferId);
  }

  // file_received ACK는 현재 attempt이며 데이터 전송이 시작된 상태일 때만 처리함. 바이트 EOF보다 먼저 도착할 수 있으므로
  // 두 조건이 모두 충족될 때 전송 완료로 확정함 (_onWireEof와 상호 합치)
  void handleFileReceived(
    String transferId, {
    required String attemptId,
    required String actorKey,
  }) {
    final source = _outgoing[transferId];
    if (source == null) return;
    final recipient = _recipientFor(source, actorKey);
    if (recipient == null || recipient.attemptId != attemptId) return;
    if (recipient.phase != _RecipientPhase.transferring &&
        recipient.phase != _RecipientPhase.awaitingAck) {
      return;
    }
    recipient.ackReceived = true;
    if (recipient.wireEof) _completeRecipient(transferId, recipient);
  }

  // 호스트가 대상 수신자에게 offer를 전달하지 못함: 해당 수신자만 재시도 가능한 실패 상태로 전환함 (그룹 방 중계 전송의 현재 attempt에만 적용)
  void handleUnavailable(
    String transferId, {
    required String attemptId,
    required String targetKey,
  }) {
    final source = _outgoing[transferId];
    if (source == null || !source.viaRelayHost) return;
    final recipient = _recipientFor(source, targetKey);
    if (recipient == null || recipient.attemptId != attemptId) return;
    if (recipient.isTerminal || recipient.phase == _RecipientPhase.failed) {
      return;
    }
    recipient.fail();
    _syncTransfer(transferId);
  }

  // 수신 측에서 재전송을 요청함: 해당 수신자만 신규 attempt로 재제안함
  Future<void> handleRetryRequested(
    String transferId, {
    required String attemptId,
    required String actorKey,
  }) async {
    final source = _outgoing[transferId];
    if (source == null) return;
    final recipient = _recipientFor(source, actorKey);
    if (recipient == null || recipient.attemptId != attemptId) return;
    if (recipient.phase != _RecipientPhase.failed &&
        recipient.phase != _RecipientPhase.cancelled) {
      return;
    }
    await _retryRecipient(transferId, source, recipient);
  }
}
