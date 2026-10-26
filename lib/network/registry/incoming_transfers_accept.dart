part of 'incoming_transfers.dart';

// 제안을 수락: 목적지를 잡고 상대에게 알림. 데스크톱은 사용자가 폴더를 고르고 모바일은 앱 문서 폴더의 IntraGram/
Future<void> _acceptIncoming(IncomingTransfers self, String transferId) async {
  final transfer = self.store.transfer(transferId);
  if (transfer == null ||
      transfer.direction != TransferDirection.incoming ||
      transfer.state != TransferState.offered) {
    return;
  }

  // 음성은 폴더를 안 물음: 보낸 기기에서 RAM으로 당겨 재생만 함 (디스크·보관소엔 안 감)
  if (transfer.voice) {
    final future = self._pullVoice(transfer);
    self._track(transferId, future);
    await future;
    return;
  }

  final attemptId = transfer.attemptId ?? transferId;
  final directory = await self._pathResolver.saveDir(
    safeBasename(transfer.fileName),
  );
  if (directory == null) return; // 사용자가 취소함
  // 폴더를 고르는 사이 정리·소각·새 attempt가 왔으면 물러남 (늦은 선택이 끝난 세션에 .part를 못 만들게)
  if (!self._isCurrent(transferId, attemptId)) return;
  // 남은 공간보다 크면 받기 전에 멈춤. 보낸 쪽엔 취소로 알려서, 공간을 비운 뒤 재시도가 새 offer를 받게 함
  final free = freeBytesAt(directory);
  if (free != null && transfer.totalBytes > free) {
    self._failForSpace(transferId);
    self
        ._linkForTransfer(transfer)
        ?.sendFileCancel(transferId, attemptId: attemptId);
    return;
  }

  // 화면에 바로 띄울 잠정 경로 (실제 이름은 커밋 때 정해짐)
  final provisional = p.join(directory, safeBasename(transfer.fileName));

  // 방 제안: 바이트는 보낸 멤버 서버에서 직접 당기고 수락만 호스트를 거쳐 알림
  final srcHost = transfer.srcHost;
  final srcPort = transfer.srcPort;
  if (srcHost != null && srcPort != null) {
    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.accepted, localPath: provisional),
    );
    // pull이면 tok은 안 쓰이지만 file_accept 필수 필드라 형식만 맞춰 새로 실음
    await self
        ._linkForTransfer(transfer)
        ?.sendFileAccept(
          transferId,
          attemptId: attemptId,
          pushToken: generateSecureToken(),
        );
    final future = self._pullDirect(
      transferId: transferId,
      host: srcHost,
      port: srcPort,
      directory: directory,
      suggestedName: transfer.fileName,
      declaredSize: transfer.totalBytes,
      attemptId: attemptId,
      authToken: transfer.pullToken ?? '',
      decrypt: self._decryptorFor(transfer),
      digest: transfer.digest,
    );
    self._track(transferId, future);
    await future;
    return;
  }

  // push: 이번 시도 전용 .part에 받음. 끝나기 전엔 최종 이름으로 안 보이고 실패하면 이것만 지우면 됨
  final (
    partial: partial,
    finalName: finalName,
  ) = await IncomingPathResolver.reserveDestination(
    directory: directory,
    name: transfer.fileName,
    attemptId: attemptId,
  );
  // 예약 직후 await 전에 소유 등록. 예약을 기다리는 사이 세션이 정리됐으면 방금 만든 .part를 바로 치움
  self._ownPartial(transferId, transfer.conversationId, attemptId, partial);
  if (!self._isCurrent(transferId, attemptId)) {
    await self._deleteOwnedPartialsRecorded(transferId);
    return;
  }
  // 상대가 POST에 다시 실어 와야 하는 수신 토큰 (서버가 비교함)
  final pushToken = generateSecureToken();
  self._incoming[transferId] = _IncomingFile(
    conversationId: transfer.conversationId,
    partial: partial,
    finalName: finalName,
    token: pushToken,
    attemptId: attemptId,
  );
  self.store.updateTransfer(
    transferId,
    (t) => t.copyWith(state: TransferState.accepted, localPath: provisional),
  );
  await self
      ._linkForTransfer(transfer)
      ?.sendFileAccept(transferId, attemptId: attemptId, pushToken: pushToken);
}

Future<void> _rejectIncoming(IncomingTransfers self, String transferId) async {
  final transfer = self.store.transfer(transferId);
  if (transfer == null) return;
  self._incoming.remove(transferId);
  self._track(transferId, self._deleteOwnedPartialsRecorded(transferId));
  self.store.updateTransfer(
    transferId,
    (t) => t.copyWith(state: TransferState.rejected),
  );
  await self
      ._linkForTransfer(transfer)
      ?.sendFileReject(transferId, attemptId: transfer.attemptId ?? transferId);
}
