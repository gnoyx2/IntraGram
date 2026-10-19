part of 'outgoing_transfers.dart';

// 상대가 우리 아웃고잉 전송에 대해 보낸 제어 프레임(accept/reject/cancel/received/retry)
// 처리. 모든 처리기는 (전송 id, 그 프레임이 가리키는 attempt,
// 인증된 발신자 키)를 받고, 그 수신자의 현재 attempt와 안 맞거나 그 수신자가 아니면 상태를 절대 안 건드림 (타이머 포함)
extension OutgoingTransfersFrames on OutgoingTransfers {
  // push면 그 수신자에게 바이트를 밀기 시작하고, pull이면 승인 의사만 기록
  // (데이터 경로는 그 수신자가 칠 GET 하나뿐이라 여기서 푸시를 시작하지 않음)
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

  // 그 수신자만 rejected. 다른 수신자의 source와 상태는
  // 그대로 (전원 종결이면 _syncTransfer가 source를 버림)
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

  // 상대가 무른 경우라 그 수신자 하나만 cancelled로 하고 피어에게 다시 알리지 않음 (우리가 취소 버튼을 누른 게 아님)
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

  // file_received ACK: 그 수신자의 현재 attempt와 일치하고 데이터 경로가 이미
  // 시작된(transferring/awaitingAck) 경우에만 인정 (낡은
  // attempt, 다른 수신자, 조기 ACK는 상태도 타이머도 안 건드림)
  // ACK는 EOF보다 먼저 올 수 있어서 곧바로 판정하지 않고 보류함: 유효한 EOF와
  // 유효한 ACK가 둘 다 확인돼야 complete (_onWireEof/여기서 합류)
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

  // 호스트가 (전송, attempt)의 offer를 targetKey 수신자에게 못 넘겼다고 알림 (대상이
  // 방에 없음/전달 실패): 그 수신자만 재시도 가능한 실패로. 방 중계로 낸 전송의 등록된 수신자이고 그
  // 현재 attempt일 때만 (낡은 attempt, 모르는 수신자, 1:1 전송의 프레임은 상태를 안 건드림)
  // 수신자의 취소가 아니라 네트워크 실패라 나중에 다시 시도할 수 있음
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

  // 받는 쪽이 실패한 시도를 다시 받고 싶다는 요청: 그 수신자만 새 attempt(+pull이면
  // 새 토큰)로 되돌려 다시 offer하고 다른 수신자는 그대로
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
