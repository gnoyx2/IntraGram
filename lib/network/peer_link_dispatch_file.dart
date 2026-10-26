part of 'peer_link.dart';

// 파일 프레임 처리. 여기 오는 건 전부 인가를 통과한 정규화 결과고, 지금 attempt·수신자 검사는 registry 처리기가 함
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

  // 영수증을 먼저 붙여 둬야 이 ACK로 완료될 때 바로 확인됨
  void _dispatchFileReceived(FileReceivedInner inner) {
    if (!_isOutgoingTransfer(inner.id)) return;
    final actor = _actor(inner.peerId);
    final receipt = inner.receipt;
    if (receipt != null) {
      onDeliveryReceipt?.call(inner.id, inner.attempt, actor, receipt);
    }
    onFileReceived?.call(inner.id, inner.attempt, actor);
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
      // 인가가 같은 발신자·같은 메타데이터의 재전송임을 이미 확인함: 같은 attempt면 멱등이라 무시, 다르면 같은 레코드를
      // 새 시도로 되돌림 (새 메시지는 안 만듦)
      if (existing.attemptId == inner.attempt) return;
      // 받은 바이트가 달라 실패한 전송('tampered')은 다시 물음: 방 멤버가 같은 큰 파일을 거듭 재제안해 계속 받게 만들 수 있음
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
      // 수락했다가 실패한 전송의 재offer는 사용자가 원한 재시도라 안 묻고 이어받음
      if (wasFailed) onAutoAcceptOffer?.call(inner.id);
      return;
    }

    final rawThumb = inner.thumb;
    store.upsertTransfer(
      FileTransfer(
        id: inner.id,
        conversationId: conversationId,
        direction: TransferDirection.incoming,
        // 상대가 정한 이름은 저장될 모양으로 받아 둠: 수락 카드에서 RLO 같은 서식 문자로 확장자를 위장 못 함
        fileName: safeBasename(inner.name),
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
        senderPubKey: inner.senderPubKey,
      ),
    );
    store.addMessage(
      EphemeralMessage(
        // transferId를 메시지 id로 씀 (보내는 쪽도 같음): 읽음·'모두에게서 삭제'가 상대 메시지에 정확히 맞으려면 필요
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

    // 검증된 상대 + 자동 수락이면 프롬프트를 건너뜀 (음성도 같음)
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
