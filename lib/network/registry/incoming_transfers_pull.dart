part of 'incoming_transfers.dart';

// 원본 기기에서 바이트를 당겨오는 두 경로: 그룹 방 멤버 직접 전송(디스크로)과 음성
// 메시지(RAM으로). 둘 다 IncomingTransfers.accept에서만 불림
extension _IncomingPull on IncomingTransfers {
  // 그룹 방 멤버 직접 전송: 원본 멤버의 GET /api/download/<id>에서 바이트를 당겨 directory
  // 안 목적지에 씀. WAN/비리터럴 호스트는 FileStreamer.download가 소켓을 열기 전에 거부
  // push 수신(_receiveIncoming)과 같은 패턴으로 이번 시도 전용 .part에 먼저 쓰고 성공해야만 최종 이름으로 커밋
  Future<void> _pullDirect({
    required String transferId,
    required String host,
    required int port,
    required String directory,
    required String suggestedName,
    required int declaredSize,
    required String attemptId,
    required String authToken,
    OpenChunk? decrypt,
    String? digest,
  }) async {
    if (!_isCurrent(transferId, attemptId)) return;
    final conversationId = store.transfer(transferId)!.conversationId;
    final (
      partial: partial,
      finalName: finalName,
    ) = await IncomingPathResolver.reserveDestination(
      directory: directory,
      name: suggestedName,
      attemptId: attemptId,
    );
    // 예약 직후 다음 await 전에 소유 등록 (예약을 기다리는 사이 세션이 정리됐다면 방금 만든 파셜을 바로 치움)
    _ownPartial(transferId, conversationId, attemptId, partial);
    if (!_isCurrent(transferId, attemptId)) {
      await _deleteOwnedPartialsRecorded(transferId);
      return;
    }
    final cancelToken = CancelToken();
    _cancelTokens[transferId] = cancelToken;
    var acquired = false;
    try {
      await gate.acquire(
        timeout: kTransferStallTimeout,
        cancelToken: cancelToken,
      );
      acquired = true;
      if (cancelToken.isCancelled) return; // 기다리는 동안 취소됨

      store.updateTransfer(
        transferId,
        (t) => t.copyWith(state: TransferState.transferring),
      );
      final written = await FileStreamer.download(
        host: host,
        port: port,
        transferId: transferId,
        attemptId: attemptId,
        authToken: authToken,
        destinationPath: partial.path,
        declaredSize: declaredSize,
        onProgress: (received, bps) => store.updateTransfer(
          transferId,
          (t) => t.copyWith(transferredBytes: received, bytesPerSecond: bps),
        ),
        decrypt: decrypt,
        cancelToken: cancelToken,
        sha256: digest,
      );
      if (cancelToken.isCancelled || !_isCurrent(transferId, attemptId)) {
        throw const TransferCancelledException();
      }
      final committed = await IncomingPathResolver.commitDestination(
        partial,
        finalName,
      );
      _releasePartial(transferId, attemptId);
      store.updateTransfer(
        transferId,
        (t) => t.copyWith(
          state: TransferState.complete,
          transferredBytes: written,
          bytesPerSecond: 0,
          localPath: committed,
        ),
      );
      final transfer = store.transfer(transferId);
      if (transfer != null) {
        await _linkForTransfer(
          transfer,
        )?.sendFileReceived(transferId, attemptId: attemptId);
      }
    } on Object catch (e) {
      // FileStreamer.download가 receive()까지 못 가고 던지면(원본이 non-200, 연결
      // 실패 등) receive()의 abort()가 안 불려
      // 파셜이 안 지워지므로 소유 registry에서 끝까지 지움
      // (이미 지워졌으면 no-op, 삭제가 실패하면 registry에 남아 다음 discard/clear가 다시 시도하고 기록됨)
      await _deleteOwnedPartialsRecorded(transferId);
      // cancelTransfer/handleCancelledByPeer가 이미 cancelled로
      // 세팅했으면 failed로 덮어쓰지 않음 (끊긴 토큰 때문에 던져진 것뿐)
      if (store.transfer(transferId)?.state != TransferState.cancelled) {
        _failReceive(transferId, e);
      }
    } finally {
      if (identical(_cancelTokens[transferId], cancelToken)) {
        _cancelTokens.remove(transferId);
      }
      if (acquired) gate.release();
    }
  }

  // 음성 메시지 수신: 원본 기기에서 오디오 바이트를 RAM으로 당겨 FileTransfer.voiceBytes에 담음 (디스크엔 안 씀)
  // WAN/비리터럴 호스트는 소켓을 열기 전에 거부하고 선언 크기를 넘는 스트림은 중단
  Future<void> _pullVoice(FileTransfer transfer) async {
    if (_closed) return;
    final host = transfer.srcHost;
    final port = transfer.srcPort;
    if (host == null || port == null) {
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(
          state: TransferState.failed,
          error: 'voice message had no source address',
        ),
      );
      return;
    }
    // 음성은 RAM으로 통째로 들어와서(파일처럼 디스크로 안 흘림) 상한을 강제함:
    // 넘게 선언한 피어는 여기서 잘리고 downloadToMemory가 초과분에서
    // 중단
    if (transfer.totalBytes > kMaxVoiceNoteBytes) {
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(
          state: TransferState.failed,
          error: 'voice message exceeds the size limit',
        ),
      );
      return;
    }
    final cancelToken = CancelToken();
    _cancelTokens[transfer.id] = cancelToken;
    var acquired = false;
    try {
      await gate.acquire(
        timeout: kTransferStallTimeout,
        cancelToken: cancelToken,
      );
      acquired = true;
      if (cancelToken.isCancelled) return; // 기다리는 동안 취소됨

      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(state: TransferState.transferring),
      );
      final bytes = await FileStreamer.downloadToMemory(
        host: host,
        port: port,
        transferId: transfer.id,
        attemptId: transfer.attemptId ?? transfer.id,
        authToken: transfer.pullToken ?? '',
        declaredSize: transfer.totalBytes,
        decrypt: _decryptorFor(transfer),
        cancelToken: cancelToken,
        sha256: transfer.digest,
      );
      if (cancelToken.isCancelled ||
          !_isCurrent(transfer.id, transfer.attemptId ?? transfer.id)) {
        SecureBytes.wipe(bytes);
        throw const TransferCancelledException();
      }
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(
          state: TransferState.complete,
          transferredBytes: bytes.length,
          bytesPerSecond: 0,
          voiceBytes: bytes,
        ),
      );
      await _linkForTransfer(transfer)?.sendFileReceived(
        transfer.id,
        attemptId: transfer.attemptId ?? transfer.id,
      );
    } on Object catch (e) {
      if (store.transfer(transfer.id)?.state != TransferState.cancelled) {
        store.updateTransfer(
          transfer.id,
          (t) => t.copyWith(
            state: TransferState.failed,
            error: classifyTransferError(e),
          ),
        );
      }
    } finally {
      if (identical(_cancelTokens[transfer.id], cancelToken)) {
        _cancelTokens.remove(transfer.id);
      }
      if (acquired) gate.release();
    }
  }
}
