part of 'outgoing_transfers.dart';

// retryTransfer 구현. 전송 mode는 유지하며 실패한 수신자별로 신규 attempt를 생성해 재제안함.
// 옛 흔적은 startNewAttempt가 다 버려서 늦게 온 옛 ACK가 새 시도를 못 끝냄
Future<void> _retryOutgoingTransfer(
  OutgoingTransfers self,
  String transferId,
) async {
  final transfer = self.store.transfer(transferId);
  final source = self._outgoing[transferId];
  if (transfer == null ||
      transfer.direction != TransferDirection.outgoing ||
      transfer.state != TransferState.failed ||
      source == null) {
    return;
  }
  if (source._recipients.isEmpty) {
    // 최초 offer 시점에 대상이 없어 실패한 전송: 현재 연결된 링크를 대상으로 처음부터 다시 제안함
    final links = self._linksForTransfer(source.conversationId);
    final endpoint = _endpointFor(self, source);
    if (links.isEmpty ||
        (source.mode == FileTransferMode.pull && endpoint == null)) {
      return;
    }
    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.offered, clearError: true),
    );
    await _offerToLinks(self, transferId, source, links, endpoint: endpoint);
    return;
  }
  for (final recipient in source._recipients.values.toList()) {
    if (recipient.phase == _RecipientPhase.failed) {
      await self._retryRecipient(transferId, source, recipient);
    }
  }
}

// pull이면 지금 서버 주소 (꺼져 있으면 null이라 재시도 못 함), push면 null
({String host, int port})? _endpointFor(
  OutgoingTransfers self,
  OutgoingFileSource source,
) => source.mode == FileTransferMode.pull ? self._localEndpoint?.call() : null;

extension _OutgoingTransfersRetry on OutgoingTransfers {
  // 해당 수신자만 신규 attempt로 재제안함. 링크가 없거나 pull 모드에서 서버가 비활성화된 경우 failed 상태를 유지함
  Future<void> _retryRecipient(
    String transferId,
    OutgoingFileSource source,
    _OutgoingRecipient recipient,
  ) async {
    final link = _linkForRecipient(source, recipient);
    final endpoint = _endpointFor(this, source);
    if (link == null ||
        (source.mode == FileTransferMode.pull && endpoint == null)) {
      return;
    }
    recipient.startNewAttempt(
      newId(),
      newPullToken: source.mode == FileTransferMode.pull
          ? generateSecureToken()
          : null,
    );
    final attemptId = recipient.attemptId;
    store.updateTransfer(transferId, (t) => t.copyWith(attemptId: attemptId));
    _syncTransfer(transferId);
    final sent = await _sendOffer(
      source,
      link,
      transferId,
      recipient,
      endpoint: endpoint,
    );
    // 전송 실패 시 다시 failed로 전환함 (그사이 신규 재시도가 시작되었으면 상태를 보존함)
    if (!sent && recipient.attemptId == attemptId) {
      recipient.fail();
      _syncTransfer(transferId);
    }
  }
}

Future<void> _handleLinkClosedOutgoing(
  OutgoingTransfers self,
  String conversationId,
  String? recipientKey,
) async {
  final ids = self._outgoing.entries
      .where((entry) => entry.value.conversationId == conversationId)
      .map((entry) => entry.key)
      .toList();
  for (final id in ids) {
    if (recipientKey == null) {
      try {
        await self.discard(id);
      } on TransferCleanupException {
        // 링크 콜백이라 실패는 _releaseFailures에만 남기고(clear가 던짐) 나머지 전송·수신 정리를 계속함
      }
      continue;
    }
    final recipient = self._outgoing[id]?._recipients[recipientKey];
    if (recipient == null || recipient.isTerminal) continue;
    recipient
      ..stopActivity()
      ..error = 'network'
      ..phase = _RecipientPhase.failed;
    self._syncTransfer(id);
  }
}

// 세션 정리: 모든 발신 소스를 개별 discard하며 진행 중인 I/O 작업 완료까지 대기함
Future<void> _clearOutgoing(OutgoingTransfers self) async {
  self._closed = true; // 이 뒤로 늦게 온 제안은 안 올림
  for (final id in self._outgoing.keys.toList()) {
    try {
      await self.discard(id);
    } on TransferCleanupException {
      // _releaseFailures에 모았으므로 다른 소스도 모두 정리한 뒤 보고함.
    }
  }
  await Future.wait(self._pendingReleases.toList());
  self._retiring.clear();
  if (self._releaseFailures.isNotEmpty) {
    final failures = List<Object>.of(self._releaseFailures);
    self._releaseFailures.clear();
    throw TransferCleanupException(failures: failures);
  }
}
