part of 'incoming_transfers.dart';

// 수락된 POST /api/transfer 바디를 수신함. 조회 → 검증 → 소비 순서이며 중간에 await가 없음: 잘못된 토큰이나 크기로는 유효 슬롯이 소모되지 않음
Future<bool> _receiveIncoming(
  IncomingTransfers self, {
  required String transferId,
  required String attemptId,
  required String token,
  required Stream<List<int>> body,
  required int headerDeclaredSize,
}) async {
  if (self._closed) return false;
  final destination = self._incoming[transferId];
  final transfer = self.store.transfer(transferId);
  if (destination == null || transfer == null) return false;
  // accept 때 발급한 토큰이어야 함 (아니면 id만 알면 아무나 바이트를 밀어 넣음)
  if (!constantTimeEquals(token, destination.token)) return false;
  // 이전 attempt의 업로드가 신규 슬롯을 점유하지 못하게 막음
  if (attemptId != destination.attemptId ||
      attemptId != (transfer.attemptId ?? transferId)) {
    return false;
  }
  // 헤더 크기는 offer 크기와 일치해야 함 (작은 헤더로 수신 대상 크기를 임의 축소하지 못하게 막음)
  if (headerDeclaredSize != transfer.totalBytes) return false;
  final declaredSize = transfer.totalBytes;

  // 검증 완료 후 슬롯을 즉시 확보함 (await 전 슬롯 소비)
  self._incoming.remove(transferId);

  final cancelToken = CancelToken();
  self._cancelTokens[transferId] = cancelToken;
  var acquired = false;
  try {
    await self.gate.acquire(
      timeout: kTransferStallTimeout,
      cancelToken: cancelToken,
    );
    acquired = true;
    if (cancelToken.isCancelled) return false; // 기다리는 동안 취소됨

    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.transferring),
    );
    // 1:1 offer엔 해시가 없어서 쓰는 대로 잰 SHA-256을 수신 영수증 커밋먼트로 씀
    String? received;
    final written = await FileStreamer.receive(
      body: body,
      transferId: transferId,
      attemptId: transfer.attemptId ?? transferId,
      destinationPath: destination.partial.path,
      declaredSize: declaredSize,
      onProgress: (received, bps) => self.store.updateTransfer(
        transferId,
        (t) => t.copyWith(transferredBytes: received, bytesPerSecond: bps),
      ),
      decrypt: self._decryptorFor(transfer),
      cancelToken: cancelToken,
      onDigest: (sha256) => received = sha256,
    );
    if (cancelToken.isCancelled || !self._isCurrent(transferId, attemptId)) {
      throw const TransferCancelledException();
    }
    final committed = await IncomingPathResolver.commitDestination(
      destination.partial,
      destination.finalName,
    );
    self._releasePartial(transferId, attemptId);
    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(
        state: TransferState.complete,
        transferredBytes: written,
        bytesPerSecond: 0,
        localPath: committed,
        contentCommitment: received,
      ),
    );
    self._acknowledge(transfer, transfer.attemptId ?? transferId, received);
    return true;
  } on Object catch (e) {
    // receive 전에 던졌으면(게이트 취소·타임아웃) abort가 안 돌아서 .part를 여기서 지움
    await self._deleteOwnedPartialsRecorded(transferId);
    // 이미 cancelled면 failed로 안 덮음 (끊긴 토큰 때문에 던진 것뿐)
    if (self.store.transfer(transferId)?.state != TransferState.cancelled) {
      self._failReceive(transferId, e);
    }
    return false;
  } finally {
    if (identical(self._cancelTokens[transferId], cancelToken)) {
      self._cancelTokens.remove(transferId);
    }
    if (acquired) self.gate.release();
  }
}

// accept가 만들고 receive·취소가 소비하는 push 수신 슬롯
class _IncomingFile {
  _IncomingFile({
    required this.conversationId,
    required this.partial,
    required this.finalName,
    required this.token,
    required this.attemptId,
  });
  final String conversationId;

  // accept 때 예약한 이번 시도 전용 .part. 실패하면 이 파일만 지움 (최종 이름은 안 건드림)
  final File partial;

  // 커밋할 목표 이름 (충돌하면 커밋 때 (n)이 붙음)
  final String finalName;

  // file_accept로 보낸 POST 토큰. 업로드가 이걸 실어 와야 함
  final String token;

  final String attemptId;
}
