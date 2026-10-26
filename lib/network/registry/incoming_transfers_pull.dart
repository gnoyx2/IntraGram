part of 'incoming_transfers.dart';

// 보낸 기기에서 당겨 오는 두 길: 방 파일(디스크로)과 음성(RAM으로). 둘 다 accept에서만 불림
extension _IncomingPull on IncomingTransfers {
  // 방 파일: 보낸 멤버의 GET /api/download/<id>에서 당김. push처럼 이번 시도 전용 .part에 쓰고 성공해야 커밋
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
    // 예약 직후 await 전에 소유 등록 (그사이 세션이 정리됐으면 바로 치움)
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
      String? received;
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
        onDigest: (sha256) => received = sha256,
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
          contentCommitment: received,
        ),
      );
      final transfer = store.transfer(transferId);
      if (transfer != null) _acknowledge(transfer, attemptId, received);
    } on Object catch (e) {
      // receive까지 못 가고 던졌으면(200 아님, 연결 실패) abort가 안 돌아서 .part를 여기서 지움
      await _deleteOwnedPartialsRecorded(transferId);
      // 이미 cancelled면 failed로 안 덮음 (끊긴 토큰 때문에 던진 것뿐)
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

  // 음성: RAM으로 당겨 voiceBytes에 담음 (디스크엔 안 씀). 선언 크기를 넘으면 끊음
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
    // RAM에 통째로 받아서 상한을 둠 (넘게 선언하면 여기서 거절)
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
      // RAM에 다 있어서 영수증 커밋먼트는 바로 잼 (방 음성은 offer 해시와 이미 맞춰 봄)
      final digest = transfer.digest ?? sha256B64(bytes);
      store.updateTransfer(
        transfer.id,
        (t) => t.copyWith(
          state: TransferState.complete,
          transferredBytes: bytes.length,
          bytesPerSecond: 0,
          voiceBytes: bytes,
          contentCommitment: digest,
        ),
      );
      _acknowledge(transfer, transfer.attemptId ?? transfer.id, digest);
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
