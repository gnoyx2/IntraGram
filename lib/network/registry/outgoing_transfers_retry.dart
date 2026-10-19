part of 'outgoing_transfers.dart';

// OutgoingTransfersDelivery.retryTransfer의 실제 구현체. 원래 mode를
// 유지하고(pull이 push로 둔갑 안 함) 실패한 수신자마다 새 attempt(+pull이면 새 토큰)로 그 수신자에게만 다시 offer
// 옛 attempt의 토큰/EOF/ACK/타이머는 startNewAttempt가 전부 버려서 늦게 오는 옛 ACK가
// 새 시도를 완료시키지 못함. 평문 재시도 경로 없음: 암호화된 전송은 항상 새 attempt로 다시 봉인함
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
    // 처음 offer 때 대상이 아무도 없어서 실패한 전송: 지금 붙어있는 링크로 처음부터 다시 offer
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

// pull이면 지금 이 기기 서버 주소, push면 null. pull인데 서버가
// 꺼져 있으면 null (받는 쪽이 당길 곳이 없어 호출부가 재시도를 못 함)
({String host, int port})? _endpointFor(
  OutgoingTransfers self,
  OutgoingFileSource source,
) => source.mode == FileTransferMode.pull ? self._localEndpoint?.call() : null;

extension _OutgoingTransfersRetry on OutgoingTransfers {
  // recipient 한 명을 새 attempt로 되돌려 그 수신자에게만 다시
  // offer. 수신자 링크가 없거나(오프라인) pull인데 서버가 꺼져 있으면
  // 아무것도 안 하고 failed로 남김
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
    // 새 attempt를 링크에 못 실었으면 offered로 기다리지 않고
    // 다시 실패로 (그 사이 더 새 재시도가 시작됐으면 그 시도는 안 건드림)
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
      await self.discard(id);
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

// 세션 teardown: 각 항목을 discard와 똑같이(진행 중 작업 await 포함) 처리한 뒤에만 맵을 비움
Future<void> _clearOutgoing(OutgoingTransfers self) async {
  self._closed = true; // 동기: 이 줄 이후 늦게 오는 제안은 stage되지 않음
  for (final id in self._outgoing.keys.toList()) {
    await self.discard(id);
  }
  await Future.wait(self._pendingReleases.toList());
  if (self._releaseFailures.isNotEmpty) {
    final failures = List<Object>.of(self._releaseFailures);
    self._releaseFailures.clear();
    throw TransferCleanupException(failures: failures);
  }
}
