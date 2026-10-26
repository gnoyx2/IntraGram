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

  // 그 수신자만 rejected (다 끝나면 _syncTransfer가 source를 버림)
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

  // 상대가 무름: 그 수신자만 cancelled (다시 알리진 않음)
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

  // file_received ACK는 지금 attempt이고 데이터가 이미 흐르기 시작했을 때만 인정. EOF보다 먼저 올 수 있어서
  // 둘 다 봐야 완료함 (_onWireEof와 여기서 만남)
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

  // 호스트가 그 수신자에게 offer를 못 넘김: 그 수신자만 재시도할 수 있는 실패로 (방 중계 전송의 지금 attempt일 때만)
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

  // 받는 쪽이 다시 받고 싶어 함: 그 수신자만 새 attempt로 다시 offer
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
