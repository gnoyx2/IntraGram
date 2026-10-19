part of 'incoming_transfers.dart';

// 수락된 POST /api/transfer의 바디를 처리. transfer id가 예상된 거고 협상한 크기 안에서 쓰기가 성공하면 true
// lookup -> 검증(token/헤더 크기) -> 소비(map에서 제거) 순서:
// 사이에 await가 없어서 틀린 토큰이나 offer와 다른 헤더 크기만으로는
// 정상 업로드 슬롯이 소모되지 않음 (같은 attempt로 다시 정확하게 보내는 재시도가 그 슬롯을 쓸 수 있어야 함)
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
  // 우리가 accept 때 발급한 값과 정확히 일치해야 함 (안 그러면 transferId를 아는 아무나 이 슬롯에 바이트를 밀어 넣음)
  // lookup만 했을 뿐 map에서 안 지웠으니 거부해도 정상 슬롯은 남음
  if (!constantTimeEquals(token, destination.token)) return false;
  // 업로드 헤더의 attempt는 이 슬롯을 만든 attempt와 같아야 함 (낡은 시도의 업로드가 새 슬롯을 소모 못 하게)
  if (attemptId != destination.attemptId ||
      attemptId != (transfer.attemptId ?? transferId)) {
    return false;
  }
  // 업로드 헤더(x-file-size)는 offer에서 이미 확정한 크기와 정확히 같아야 함
  // (min(header, offer)면 더 작은 헤더가 조용히 강제 크기를 줄일 수 있었음)
  // 서버가 헤더 누락/파싱 실패는 이미 걸러서 필수 int로 넘김
  if (headerDeclaredSize != transfer.totalBytes) return false;
  final declaredSize = transfer.totalBytes;

  // 여기서부터 실제로 슬롯을 소비함 (검증이 전부 끝난 뒤, await 전에)
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
      ),
    );
    await self
        ._linkForTransfer(transfer)
        ?.sendFileReceived(
          transferId,
          attemptId: transfer.attemptId ?? transferId,
        );
    return true;
  } on Object catch (e) {
    // gate.acquire()가 FileStreamer.receive() 호출 전에 던지면(취소/timeout)
    // receive()의 abort()가 안 불려 파셜이 안 지워지므로 소유 registry에서 끝까지 지움
    // (이미 지워졌으면 no-op, 삭제가 실패하면 registry에 남아 다음 discard/clear가 다시 시도하고 기록됨)
    await self._deleteOwnedPartialsRecorded(transferId);
    // cancelTransfer/handleCancelledByPeer가 이미 cancelled로
    // 세팅했으면 failed로 덮어쓰지 않음 (끊긴 토큰 때문에 던져진 것뿐)
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

// IncomingTransfers._incoming의 값 타입: accept가 등록하고
// receive/취소가 소비
class _IncomingFile {
  _IncomingFile({
    required this.conversationId,
    required this.partial,
    required this.finalName,
    required this.token,
    required this.attemptId,
  });
  final String conversationId;

  // 이번 시도 전용 .intragram-<attempt>.part: accept
  // 시점에 exclusive create로 미리 예약. 실제 바이트는 여기에 쓰고,
  // 실패하면 FileStreamer.receive의 abort()가 이
  // 파일(자기가 쓴 파일 그 자체)만 지움 (최종 이름은 절대 안 건드림)
  final File partial;

  // 완료 시 commitDestination에 넘길 목표 이름 (충돌하면
  // 커밋 시점에 (n) 접미사가 붙을 수 있고 그건 커밋 결과로 확정)
  final String finalName;

  // accept 때 우리가 발급해 file_accept로 돌려보낸 POST
  // /api/transfer 인가 토큰: 실제 업로드가 이 값을 실어 와야
  // 함
  final String token;

  // 이 슬롯을 만든 offer의 시도 id (업로드 헤더의 attempt와 일치해야 함)
  final String attemptId;
}
