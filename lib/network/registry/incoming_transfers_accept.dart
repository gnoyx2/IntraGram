part of 'incoming_transfers.dart';

// 인커밍 제안을 수락하고 서버가 바이트를 받게 목적지를 등록한 뒤 피어에게 알림. 데스크톱에선 유저가 폴더를 고르고,
// 모바일은 앱 문서 디렉토리 밑 IntraGram/에 떨어져 resolve된 경로가 채팅에 뜸
Future<void> _acceptIncoming(IncomingTransfers self, String transferId) async {
  final transfer = self.store.transfer(transferId);
  if (transfer == null ||
      transfer.direction != TransferDirection.incoming ||
      transfer.state != TransferState.offered) {
    return;
  }

  // 음성 메시지: 폴더를 안 물어봄. 원본 기기 서버에서 RAM으로 바로 당겨 재생만 함 (디스크/보관소에 안 감)
  // srcHost/srcPort가 제안에 박혀 있어야 함
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
  if (directory == null) return; // 유저가 취소했거나 목적지 없음
  // 폴더 선택을 기다리는 사이 clear/소각/새 attempt가 왔으면
  // 물러남: 늦게 돌아온 선택이 정리가 끝난 세션에 .part를 만들지 못하게
  if (!self._isCurrent(transferId, attemptId)) return;
  // 선언 크기가 남은 공간을 넘으면 받기 전에 멈춤 (끝까지 받다 같은 실패를 보지 않게). 보낸 쪽엔
  // 취소로 알려서 공간을 비운 뒤 받는 쪽 재시도(file_retry)가 새 offer를 받게 함
  final free = freeBytesAt(directory);
  if (free != null && transfer.totalBytes > free) {
    self._failForSpace(transferId);
    self
        ._linkForTransfer(transfer)
        ?.sendFileCancel(transferId, attemptId: attemptId);
    return;
  }

  // 화면에 즉시 보여줄 잠정 경로: 실제 커밋된 이름은 전송 완료 시
  // commitDestination이 (충돌하면 접미사 붙여) 다시 알려줌
  // 지금은 아직 아무 파일도 안 쓰는 순수 경로 계산
  final provisional = p.join(directory, safeBasename(transfer.fileName));

  // 그룹 방 제안: 호스트를 안 거치고 원본 멤버 서버에서 바이트를 직접 당김.
  // 수락은 여전히 호스트 경유로 알림 (진행 표시 + 그 offer의 수신자로 기록)
  final srcHost = transfer.srcHost;
  final srcPort = transfer.srcPort;
  if (srcHost != null && srcPort != null) {
    self.store.updateTransfer(
      transferId,
      (t) => t.copyWith(state: TransferState.accepted, localPath: provisional),
    );
    // pull의 accept는 승인 의사 표시일 뿐이지만 file_accept의 tok은 프로토콜상
    // 항상 필수라 형식만 맞춰 새로 발급해 실음 (보내는 쪽은 pull이면 이 값을 안 씀)
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

  // push: 목적지는 이번 시도(attemptId) 전용 .part 파일이라
  // 완료 전엔 최종 이름으로 절대 안 보이고, 실패하면 이 파셜만 지우면 됨
  final (
    partial: partial,
    finalName: finalName,
  ) = await IncomingPathResolver.reserveDestination(
    directory: directory,
    name: transfer.fileName,
    attemptId: attemptId,
  );
  // push 수신 인가 토큰: 우리가 발급해 accept에 실어 보냄. 상대는 POST할
  // 때 이 값(과 attempt)을 다시 실어 와야 하고 서버가 이 값과 비교함
  // (server_routes.dart의 _receiveFile 참고)
  // 예약 직후 다음 await 전에 소유 등록하고, 예약을 기다리는 사이 세션이 정리됐다면 방금 만든 파셜을 바로 치움
  self._ownPartial(transferId, transfer.conversationId, attemptId, partial);
  if (!self._isCurrent(transferId, attemptId)) {
    await self._deleteOwnedPartialsRecorded(transferId);
    return;
  }
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
