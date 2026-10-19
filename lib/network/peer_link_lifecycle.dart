part of 'peer_link.dart';

// 링크 종료 경로: 프레임 pause/resume 드레인과 실제 종료(cleanup).
// PeerLink.close/내부 오류 경로가 전부 여기로 모여
// _closeFuture 하나로 멱등 await됨 (동시 호출자 전원이 진짜 cleanup 완료를 같이 기다림)
extension _PeerLinkLifecycle on PeerLink {
  // 도착한 프레임마다 구독을 멈췄다가 처리가 끝나면 재개해서 한 번에 한 프레임만 처리되게 강제함
  // _onFrame이 여러 await(핸드셰이크, 복호화)를 거치는 동안
  // 다음 프레임이 끼면 phase 검사/_lastSeenSeq 갱신 사이에
  // 경합이 생길 수 있음 (무한 Future chain에 프레임을 쌓지도 않음)
  void _onRawFrame(dynamic raw) {
    _subscription?.pause();
    _onFrame(raw).catchError((Object _) => _shutdown()).whenComplete(() {
      if (!_closed) _subscription?.resume();
    });
  }

  Future<void> _shutdown() => _closeFuture ??= _performShutdown();

  Future<void> _performShutdown() async {
    // 끝내 누구인지 밝히지 않고 끊긴 인바운드 소켓인가 (_phase를 바꾸기 전에 봄)
    final unidentified = !dialledByUs && isPendingHandshake;
    _closed = true;
    _phase = _LinkPhase.closed;
    _awaitingAuth = null;
    _handshakeWatchdog?.cancel();
    // 못 나간 대기 큐와 확인 못 받은 내 메시지는 재시도할 수 있게 failed로 (이 링크로는 ack가 더 안 옴)
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
      // half-open 채널(피어가 자기 쪽을 안 읽음)이 teardown을 막으면 안 됨
      await channel.sink.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } on Object {
      // 이미 사라짐
    }
    // registry가 이 링크를 이미 다른 링크로 대체했으면(재연결/재합류 경합) 늦게 도착한 이 종료가
    // 새 링크의 online/typing/메시지 상태를 덮어쓰지 않음 (소켓/구독/크립토는 위에서 이미 정리됨)
    final tile = store.conversation(conversationId);
    if (!_superseded &&
        unidentified &&
        tile != null &&
        !tile.isRoom &&
        store.messages(conversationId).isEmpty) {
      // 연결만 열고 닫는 반복이 목록을 빈 "peer" 대화로 채우지 못하게 함
      // (버전 불일치 같은 안내 줄이 남은 대화와 방 대화는 아래 일반 경로로 둠)
      store.wipeConversation(conversationId);
    } else if (!_superseded) {
      store.setConversationOnline(conversationId, online: false);
      store.setPeerTyping(conversationId, typing: false);
      // 대화가 아직 있을 때만 (패닉 와이프 중이면 이미 사라짐: 빈 방 되살리지 않음)
      // 내가 다이얼한 핸드셰이크가 실패했으면 이유 줄로 대신함
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
