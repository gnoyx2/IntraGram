part of 'peer_link.dart';

// _PeerLinkDispatch 중 파일 전송 프레임(file_*) 처리. 여기 오는 프레임은 전부
// _PeerLinkAuthorization을 이미 통과한 정규화 결과 (소속/방 역할/충돌/downgrade 검사 끝)
// 현재 attempt/수신자 검사는 상태를 아는 registry 처리기가 하고, 여기선 (id, attempt, 인증된 발신자)를
// 그대로 넘기기만 하고 store 상태는 안 건드림
extension _PeerLinkDispatchFile on PeerLink {
  String _actor(String? peerId) => peerId ?? remotePeerId ?? peerAlias;

  bool _isOutgoingTransfer(String id) =>
      store.transfer(id)?.direction == TransferDirection.outgoing;

  void _dispatchFileOffer(FileOfferInner inner) => _ingestFileOffer(inner);

  void _dispatchFileAccept(FileAcceptInner inner) {
    if (!_isOutgoingTransfer(inner.id)) return;
    onFileAccepted?.call(
      inner.id,
      inner.attempt,
      inner.token,
      _actor(inner.peerId),
    );
  }

  void _dispatchFileReject(FileRejectInner inner) {
    if (!_isOutgoingTransfer(inner.id)) return;
    onFileRejected?.call(inner.id, inner.attempt, _actor(inner.peerId));
  }

  // 취소는 양방향: 방향 판단(내가 보내는 쪽인지)과 attempt/발신자 검사는 registry가 함
  void _dispatchFileCancel(FileCancelInner inner) =>
      onFileCancelled?.call(inner.id, inner.attempt, _actor(inner.peerId));

  void _dispatchFileReceived(FileReceivedInner inner) {
    if (!_isOutgoingTransfer(inner.id)) return;
    onFileReceived?.call(inner.id, inner.attempt, _actor(inner.peerId));
  }

  void _dispatchFileRetry(FileRetryInner inner) {
    if (!_isOutgoingTransfer(inner.id)) return;
    onFileRetryRequested?.call(inner.id, inner.attempt, _actor(inner.peerId));
  }

  // 내가 보낸 전송인지만 보고, 대상 수신자/현재 attempt 검사는 registry가 함
  void _dispatchFileUnavailable(FileUnavailableInner inner) {
    if (!_isOutgoingTransfer(inner.id)) return;
    onFileUnavailable?.call(inner.id, inner.attempt, inner.target);
  }

  void _ingestFileOffer(FileOfferInner inner) {
    final existing = store.transfer(inner.id);
    if (existing != null) {
      // 인가 단계가 "같은 발신자/같은 메타데이터의 재전송"임을 이미 확인함: 같은 attempt면 멱등 재전송(아무것도 안 함),
      // 다르면 보내는 쪽이 새 attempt/토큰으로 다시 협상한 것이라 같은
      // 레코드를 새 시도로 되돌림(진행률/에러 초기화) 새 레코드/메시지는 안 만듦
      if (existing.attemptId == inner.attempt) return;
      // 받은 바이트가 제안과 달라 실패한 전송('tampered')은 다시 물음: 방의 다른 멤버가 같은 큰 파일을
      // 거듭 재제안해 받는 쪽이 계속 내려받게 만들 수 있음
      final wasFailed =
          existing.state == TransferState.failed &&
          existing.error != 'tampered';
      store.updateTransfer(
        inner.id,
        (t) => t.copyWith(
          state: TransferState.offered,
          transferredBytes: 0,
          bytesPerSecond: 0,
          clearError: true,
          attemptId: inner.attempt,
          pullToken: inner.token,
          srcHost: inner.srcHost,
          srcPort: inner.srcPort,
        ),
      );
      // 받는 쪽이 이미 수락했다가 실패한 전송의 재offer(내가 file_retry를 보냈거나 보내는 쪽이 재시도)는
      // 사용자가 원한 재시도라 다시 안 묻고 이어받음. 아직 수락 전(offered)이면 그대로 수락/거절 프롬프트
      if (wasFailed) onAutoAcceptOffer?.call(inner.id);
      return;
    }

    final rawThumb = inner.thumb;
    store.upsertTransfer(
      FileTransfer(
        id: inner.id,
        conversationId: conversationId,
        direction: TransferDirection.incoming,
        fileName: inner.name,
        totalBytes: inner.size,
        mimeType: inner.mime,
        state: TransferState.offered,
        srcHost: inner.srcHost,
        srcPort: inner.srcPort,
        thumbBytes: rawThumb == null ? null : _decodeThumbBytes(rawThumb),
        preview: inner.preview,
        voice: inner.voice,
        encrypted: inner.enc,
        batchId: inner.batchId,
        attemptId: inner.attempt,
        pullToken: inner.token,
        mode: inner.mode == 'pull'
            ? FileTransferMode.pull
            : FileTransferMode.push,
        senderPeerId: _actor(inner.peerId),
        digest: inner.digest,
      ),
    );
    store.addMessage(
      EphemeralMessage(
        // transferId(= inner.id)를 그대로 메시지 id로
        // 씀 (보내는 쪽도 같은 id를 씀, outgoing_transfers.dart)
        // 읽음 영수증과 "모두에게서 삭제" burn 프레임이 상대 메시지에 정확히 매칭되려면 필요
        id: inner.id,
        conversationId: conversationId,
        direction: MessageDirection.incoming,
        kind: MessageKind.file,
        senderAlias: inner.from ?? peerAlias,
        createdAt: DateTime.now(),
        transferId: inner.id,
        ttlSeconds: inner.ttlSeconds.clamp(0, 24 * 3600),
        delivery: DeliveryState.sent,
      ),
    );
    store.bumpUnread(conversationId);

    // 검증된 피어 + 자동 수락 켜짐이면 수락/거절 프롬프트를 건너뜀 (음성도 같은 규칙: 수락 없이 받아지는 건 의도와 달랐음)
    final conversation = store.conversation(conversationId);
    if ((conversation?.autoAcceptFiles ?? false) &&
        (conversation?.verified ?? false)) {
      onAutoAcceptOffer?.call(inner.id);
    }
  }
}

// 망가졌으면 null (미리보기만 없어짐)
Uint8List? _decodeThumbBytes(String b64) {
  try {
    return base64.decode(b64);
  } on FormatException {
    return null;
  }
}
