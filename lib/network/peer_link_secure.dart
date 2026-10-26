part of 'peer_link.dart';

// 증명이 끝난 링크를 앱 피어로 확정: 신원·SAS를 store에 적고 대기열을 비움
extension _PeerLinkSecure on PeerLink {
  Future<void> _finishPeerHello(HelloOuter hello) async {
    final crypto = _crypto;
    if (_closed || crypto == null || !crypto.isReady) return;
    remotePeerId = hello.peerId;
    _remoteIdentityKey = Uint8List.fromList(
      hello.identityKey,
    ).asUnmodifiableView();
    peerAlias = hello.alias;
    peerPlatform = hello.platform;
    transport = PeerTransport.app;
    // 같은 host로 다시 붙은 앱 피어(재연결)면 기존 대화로 옮겨 탐. conversationId가 바뀌어서 store 쓰기보다 먼저 함
    onAppPeerIdentified?.call();

    _phase = _LinkPhase.app;
    final stillVerified = _carryVerification(hello.peerId);
    onSecure?.call();
    _handshakeWatchdog?.cancel();

    // 방 합류 뒤면 conversationId가 방이라 이 링크 상대의 멤버 슬롯에 SAS를 적음 (대화 하나를 여러 링크가 나눠 씀)
    final isRoomLink = store.conversation(conversationId)?.isRoom ?? false;
    final sas = crypto.sasDigits;
    if (sas != null) {
      if (isRoomLink && remotePeerId != null) {
        store.setRoomMemberSas(conversationId, remotePeerId!, sas);
      } else {
        store.setConversationSas(conversationId, sas);
      }
    }

    store.updateConversation(
      conversationId,
      (c) => c.copyWith(
        peerAlias: peerAlias,
        peerPlatform: peerPlatform,
        peerTyping: false,
        secure: crypto.isReady,
        online: true,
        // 인바운드면 remotePort는 accept가 본 ephemeral 포트라 hello의 진짜 리스닝 포트로 덮음 (파일 다시 밀 때 다이얼할 포트)
        peerPort: hello.port ?? c.peerPort,
        // 방이면 peerId를 변경하지 않음 (RoomMember가 각자 관리함). 1:1이면 IP가 바뀌어도 재연결 시 동일 피어인지 식별할 수 있도록 기록해 둠
        peerId: isRoomLink ? null : hello.peerId,
      ),
    );
    _flushPending();
    _startOrgAttestation();
    unawaited(_sendOwedReceipts());
    if (stillVerified) unawaited(sendRawInnerOrClose(InnerFrame.verify()));
  }

  // 1:1에 예전 코드가 있으면 재연결. 재연결은 이 대화 peerId(신원 키 해시)를 다시 증명해야 이어지고 새 세션 키는 그 신원 키 서명에 묶임:
  // 전에 내가 확인한 신원 그대로면 그 확인을 이어 가고(true면 상대에게 verify 다시 보냄) 아니면 지우고 코드가 바뀐 이유를 알림.
  // 상대 확인은 이번 세션에서 상대가 다시 알려야 켜짐
  bool _carryVerification(String peerId) {
    final previous = store.conversation(conversationId);
    final again = previous != null && !previous.isRoom && previous.sas != null;
    final keep = again && previous.localVerified && previous.peerId == peerId;
    _carried = keep;
    if (again) {
      store.updateConversation(
        conversationId,
        (c) => c.copyWith(localVerified: keep, peerVerified: false),
      );
    }
    store.addSystemMessage(
      conversationId,
      SystemEvent(
        keep
            ? SystemEventKind.verifiedAgain
            : again
            ? SystemEventKind.encryptedAgain
            : SystemEventKind.encrypted,
      ),
    );
    return keep;
  }
}
