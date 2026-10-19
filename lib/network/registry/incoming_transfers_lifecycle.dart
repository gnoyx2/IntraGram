part of 'incoming_transfers.dart';

// IncomingTransfers의 배치/취소/재시도/정리 실제 구현체 (문서는 각 public 메서드 시그니처에 있음)
// top-level 함수 + self 파라미터로 쓰는 이유: extension은 호출부가 incoming_transfers.dart를
// 직접 import 안 하면 스코프 밖이라 못 씀

// batchId에서 아직 offered인 인커밍 전송 전부를 수락. 이미
// 개별적으로 수락/거절된 형제는 안 건드리고 accept를 그대로 재사용
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

// offered는 여기서 안 다룸 (reject가 있음). 전송 중이면 토큰을
// 끊어 다음 청크에서(정지한 스트림이면 구독 취소로 즉시) I/O가 중단되게 함
// UI 응답성 우선으로 즉시 상태를 갱신하고, 진행 중이던 I/O가 끝난 뒤의 소유 파셜 삭제는 추적되는 작업으로 뒤따라감
// (discard/clear가 그 끝까지 기다릴 수 있음). 살아있는 링크가 있으면 피어에게도 알림
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

// 토큰을 끊고 받기 슬롯을 치우고 진행 중이던 작업이 끝난 뒤 소유 파셜을 지우는 정리 작업을 추적 등록
// 취소가 실제 바이트가 오기도 전에(accept 직후 서버 POST 대기 중) 왔으면
// _cancelTokens엔 아직 아무것도 없어 .cancel()이 no-op이지만,
// 예약한 파셜은 registry에 있으니 여기서 치움
void _stopAndCleanUp(IncomingTransfers self, String transferId) {
  self._cancelTokens[transferId]?.cancel();
  self._incoming.remove(transferId);
  final previous = self._active[transferId];
  self._track(transferId, () async {
    if (previous != null) await previous;
    await self._deleteOwnedPartialsRecorded(transferId);
  }());
}

// future를 transferId의 진행 중 작업으로 등록하고 끝나면(성공/실패 무관)
// 자기 자신을 지움. 그사이 같은 id로 더 새 작업이 등록됐으면(재시도 경합)
// 그 새 작업을 안 건드림 (identical로 "내가 지금도 최신 등록자인가"만 확인)
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

// 그 링크의 대화(와 그룹 방이면 senderPeerId 발신자)에 속한 전송만 _discard와 똑같이 정리: 다른 멤버의 수신은 그대로
// 던질 곳이 없는 경로(링크 콜백)라 정리 실패는 기록만 하고 clear가 마지막에 보고
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

// 세션 teardown: admission부터 동기적으로 닫고(새 accept/pull/receive 거부) 남은 전송 전부를 취소 ->
// 진행 중 I/O가 끝날 때까지 대기 -> 소유 파셜만 삭제 순으로 정리한 뒤 완료됨 (성공한 최종 파일과 사용자 파일은 안 건드림)
// 삭제 실패는 삼키지 않고 마지막에 TransferCleanupException으로 모아 던짐
Future<void> _clearIncoming(IncomingTransfers self) async {
  self._closed = true;
  final ids = self._ownedTransferIds().toList();
  for (final id in ids) {
    self._cancelTokens[id]?.cancel();
  }
  final failures = <Object>[];
  for (final id in ids) {
    // 이번 discard가 partial을 다시 지워 보고 그 결과를
    // 직접 보고하므로, 옛 배경 실패 기록과 중복해서 세지 않게 먼저
    // 치움
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

// 스토어에서 transferId가 이미 사라진 뒤(소각/전체 와이프) 불림: _cancelTransfer와 달리
// store.transfer(transferId)를 다시 조회하지 않음 (그 레코드가 이미 없어 가드가 항상 실패)
// 순서: 토큰 cancel -> 진행 중이던 I/O가 실제로 끝나길 await -> 슬롯
// 제거 -> 소유 파셜 삭제 (실패하면 TransferCleanupException)
Future<void> _discard(IncomingTransfers self, String transferId) async {
  self._cancelTokens[transferId]?.cancel();
  final active = self._active[transferId];
  if (active != null) await active;
  self._incoming.remove(transferId);
  await self._deleteOwnedPartials(transferId);
}

// 우리 쪽 취소 버튼이 아니라 상대가 무른 경우. offered도 포함 (아직 수락/거절 안 한 제안을 상대가 먼저 접었을 수 있음)
// _cancelTransfer와 대칭이지만 피어에게 다시 알리지 않음
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
  // 그 전송의 실제 발신자가 지금 진행 중인 시도를 무를 때만: 다른 멤버나 낡은 attempt의 취소가 남의/새 전송을 끊지 못하게
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

// 옛 토큰/attempt를 재사용하지 않고 보내는 쪽에 file_retry로 새 attempt/토큰의
// 재offer를 요청. 새 offer가 (같은 id, 새 attempt로) 오면
// PeerLink가 자동 수락해서 이어감 (중복 GET/취소 뒤 재사용 금지, 재시도는 새 attempt와 새 token 협상)
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
