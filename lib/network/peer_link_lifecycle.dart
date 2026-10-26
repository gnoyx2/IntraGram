part of 'peer_link.dart';

// 종료 경로: 프레임을 하나씩 처리하는 pause/resume과 실제 정리. 모든 종료가 _closeFuture 하나로 모임
extension _PeerLinkLifecycle on PeerLink {
  // 프레임마다 구독을 멈췄다 처리가 끝나면 재개: _onFrame이 await를 거치는 사이 다음 프레임이 끼면 phase·_lastSeenSeq 검사가 꼬임
  void _onRawFrame(dynamic raw) {
    _subscription?.pause();
    _onFrame(raw).catchError((Object _) => _shutdown()).whenComplete(() {
      if (!_closed) _subscription?.resume();
    });
  }

  Future<void> _shutdown() => _closeFuture ??= _performShutdown();

  Future<void> _performShutdown() async {
    // 끝내 누군지 안 밝히고 끊긴 인바운드 소켓인가 (_phase 바꾸기 전에 봄)
    final unidentified = !dialledByUs && isPendingHandshake;
    _closed = true;
    _stopOrgAttestation();
    _phase = _LinkPhase.closed;
    _awaitingAuth = null;
    _handshakeWatchdog?.cancel();
    // 못 나간 대기 큐와 ack 못 받은 내 메시지는 다시 보낼 수 있게 failed로
    for (final inner in _pending) {
      _noteWrite(inner, written: false);
      _reowe(inner);
    }
    for (final id in _unacked) {
      if (store.messageById(id)?.delivery == DeliveryState.sent) {
        store.setDelivery(id, DeliveryState.failed);
      }
    }
    _unacked.clear();
    _pending.clear();
    _pendingBytes = 0;
    await _subscription?.cancel();
    _crypto?.destroy();
    _crypto = null;
    try {
      // 상대가 안 읽는 반쯤 열린 채널이 정리를 막으면 안 됨
      await channel.sink.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } on Object {
      // 이미 사라짐
    }
    // 이미 다른 링크로 대체됐으면 늦게 온 이 종료가 새 링크 상태를 안 덮음
    final tile = store.conversation(conversationId);
    if (!_superseded &&
        unidentified &&
        tile != null &&
        !tile.isRoom &&
        store.messages(conversationId).isEmpty) {
      // 연결만 열고 닫는 반복으로 목록이 빈 'peer' 대화로 차는 걸 막음 (안내 줄이 남은 대화·방은 아래로)
      store.wipeConversation(conversationId);
    } else if (!_superseded) {
      store.setConversationOnline(conversationId, online: false);
      store.setPeerTyping(conversationId, typing: false);
      // 대화가 남아 있을 때만 (패닉 중이면 이미 없음: 빈 방 안 되살림). 내가 다이얼한 핸드셰이크가 실패했으면 그 이유 줄로
      if (store.conversation(conversationId) != null) {
        store.addSystemMessage(
          conversationId,
          SystemEvent(
            (dialledByUs ? _failReason : null) ?? SystemEventKind.disconnected,
          ),
        );
      }
    }
    onClosed?.call(this);
  }

  // 링크가 없던 사이 못 간 읽음·소각을 보냄. 하나씩 기다려 대기 상한을 안 넘기고, 못 나간 나머지는 다음 링크 몫
  Future<void> _sendOwedReceipts() async {
    final owed = store.takeOwed(conversationId);
    final frames = [
      for (final id in owed.reads) InnerFrame.read(id),
      for (final id in owed.burns) InnerFrame.burn(id),
    ];
    for (var i = 0; i < frames.length; i++) {
      if (!await sendRawInnerOrClose(frames[i])) {
        frames.skip(i).forEach(_reowe);
        return;
      }
    }
  }

  // 1:1만 다시 적음: 방은 호스트가 멤버마다 따로 중계해서 이 링크 하나로 갚을 수 없음
  void _reowe(Map<String, dynamic> inner) {
    final id = inner['id'];
    if (id is! String || (store.conversation(conversationId)?.isRoom ?? true)) {
      return;
    }
    switch (inner['k']) {
      case 'read':
        store.oweReads(conversationId, [id]);
      case 'burn':
        store.oweBurn(conversationId, id);
    }
  }
}
