part of 'incoming_transfers.dart';

// 배치·취소·재시도·정리 구현 (공개 메서드는 IncomingTransfers에 있고 여기로 넘김)

// 배치에서 아직 offered인 것만 수락 (따로 수락·거절한 건 안 건드림)
Future<void> _acceptBatch(
  IncomingTransfers self,
  String conversationId,
  String batchId,
) async {
  final siblings = self.store
      .transfersInBatch(conversationId, batchId)
      .where(
        (t) =>
            t.direction == TransferDirection.incoming &&
            t.state == TransferState.offered,
      );
  for (final t in siblings) {
    await self.accept(t.id);
  }
}

Future<void> _rejectBatch(
  IncomingTransfers self,
  String conversationId,
  String batchId,
) async {
  final siblings = self.store
      .transfersInBatch(conversationId, batchId)
      .where(
        (t) =>
            t.direction == TransferDirection.incoming &&
            t.state == TransferState.offered,
      );
  for (final t in siblings) {
    await self.reject(t.id);
  }
}

// 수락한 뒤의 취소 (offered는 reject). 토큰을 끊어 I/O를 멈추고 상태는 바로 바꿈. .part 삭제는 I/O가 끝난 뒤 추적되는 작업으로 따라감
void _cancelTransfer(IncomingTransfers self, String transferId) {
  final transfer = self.store.transfer(transferId);
  if (transfer == null || transfer.direction != TransferDirection.incoming) {
    return;
  }
  if (transfer.state != TransferState.accepted &&
      transfer.state != TransferState.transferring) {
    return;
  }
  _stopAndCleanUp(self, transferId);
  self.store.updateTransfer(
    transferId,
    (t) => t.copyWith(state: TransferState.cancelled),
  );
  self
      ._linkForTransfer(transfer)
      ?.sendFileCancel(transferId, attemptId: transfer.attemptId ?? transferId);
}

// 토큰을 끊고 슬롯을 치운 뒤, 도는 작업이 끝나면 .part를 지우는 작업을 추적함 (바이트가 오기 전 취소여도 예약한 .part는 여기서 치움)
void _stopAndCleanUp(IncomingTransfers self, String transferId) {
  self._cancelTokens[transferId]?.cancel();
  self._incoming.remove(transferId);
  final previous = self._active[transferId];
  self._track(transferId, () async {
    if (previous != null) await previous;
    await self._deleteOwnedPartialsRecorded(transferId);
  }());
}

// 진행 중 작업으로 등록하고 끝나면 스스로 지움. 그사이 더 새 작업이 등록됐으면 그건 안 건드림
void _trackIncoming(
  IncomingTransfers self,
  String transferId,
  Future<void> future,
) {
  final tracked = future.then<void>((_) {}, onError: (_) {});
  self._active[transferId] = tracked;
  unawaited(
    tracked.whenComplete(() {
      if (identical(self._active[transferId], tracked)) {
        self._active.remove(transferId);
      }
    }),
  );
}

// 그 대화(방이면 그 발신자) 전송만 정리하고 다른 멤버 수신은 둠. 링크 콜백이라 실패는 기록만 하고 clear가 던짐
Future<void> _handleLinkClosedIncoming(
  IncomingTransfers self,
  String conversationId,
  String? senderPeerId,
) async {
  final ids = self
      ._ownedTransferIds()
      .where(
        (id) =>
            self._conversationOf(id) == conversationId &&
            (senderPeerId == null ||
                self.store.transfer(id)?.senderPeerId == senderPeerId),
      )
      .toList();
  for (final id in ids) {
    try {
      await _discard(self, id);
    } on TransferCleanupException catch (e) {
      self._cleanupFailures[id] = e.failures;
    }
  }
}

// 세션 정리: 입구를 닫고 → 다 취소 → I/O가 끝나길 기다림 → .part만 지움 (받은 파일·사용자 파일은 안 건드림). 실패는 모아서 던짐
Future<void> _clearIncoming(IncomingTransfers self) async {
  self._closed = true;
  final ids = self._ownedTransferIds().toList();
  for (final id in ids) {
    self._cancelTokens[id]?.cancel();
  }
  final failures = <Object>[];
  for (final id in ids) {
    // 이번 discard가 다시 지워 보고 직접 보고하니 옛 기록은 먼저 치움 (두 번 안 셈)
    self._cleanupFailures.remove(id);
    try {
      await _discard(self, id);
    } on TransferCleanupException catch (e) {
      failures.addAll(e.failures);
    }
  }
  self._pathResolver.clear();
  for (final leftover in self._cleanupFailures.values) {
    failures.addAll(leftover);
  }
  self._cleanupFailures.clear();
  if (failures.isNotEmpty) throw TransferCleanupException(failures: failures);
}

// 스토어에서 이미 사라진 뒤에도 불려서 store를 다시 안 봄. 토큰 끊기 → I/O 끝나길 기다림 → 슬롯 제거 → .part 삭제
Future<void> _discard(IncomingTransfers self, String transferId) async {
  self._cancelTokens[transferId]?.cancel();
  final active = self._active[transferId];
  if (active != null) await active;
  self._incoming.remove(transferId);
  await self._deleteOwnedPartials(transferId);
}

// 상대가 무름. offered도 포함 (답하기 전에 상대가 접었을 수 있음). 상대에게 다시 알리진 않음
void _handleCancelledByPeer(
  IncomingTransfers self,
  String transferId,
  String attemptId,
  String senderPeerId,
) {
  final transfer = self.store.transfer(transferId);
  if (transfer == null || transfer.direction != TransferDirection.incoming) {
    return;
  }
  // 실제 발신자가 지금 시도를 무를 때만 (다른 멤버나 옛 attempt의 취소가 남의 전송을 못 끊게)
  if (transfer.senderPeerId != senderPeerId ||
      (transfer.attemptId ?? transferId) != attemptId) {
    return;
  }
  if (transfer.state != TransferState.offered &&
      transfer.state != TransferState.accepted &&
      transfer.state != TransferState.transferring) {
    return;
  }
  _stopAndCleanUp(self, transferId);
  self.store.updateTransfer(
    transferId,
    (t) => t.copyWith(state: TransferState.cancelled),
  );
}

// 옛 토큰·attempt는 안 쓰고 file_retry로 재offer를 부탁함. 같은 id에 새 attempt로 오면 PeerLink가 알아서 받음
Future<void> _retryTransfer(IncomingTransfers self, String transferId) async {
  final transfer = self.store.transfer(transferId);
  if (transfer == null ||
      transfer.direction != TransferDirection.incoming ||
      transfer.state != TransferState.failed) {
    return;
  }
  await self
      ._linkForTransfer(transfer)
      ?.sendFileRetry(transferId, attemptId: transfer.attemptId ?? transferId);
}
