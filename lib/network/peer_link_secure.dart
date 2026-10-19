part of 'peer_link.dart';

// 신원 증명이 끝난 링크를 앱 피어로 확정: 상대 신원·SAS를 store에 적고 대기열을 비움
extension _PeerLinkSecure on PeerLink {
  Future<void> _finishPeerHello(HelloOuter hello) async {
    final crypto = _crypto;
    if (_closed || crypto == null || !crypto.isReady) return;
    remotePeerId = hello.peerId;
    peerAlias = hello.alias;
    peerPlatform = hello.platform;
    transport = PeerTransport.app;
    // 같은 host로 다시 붙은 앱 피어(재연결)면 기존 대화로 옮겨 탐. conversationId가 바뀌어서 store 쓰기보다 먼저 함
    onAppPeerIdentified?.call();

    _phase = _LinkPhase.app;
    final stillVerified = _carryVerification(hello.peerId);
    onSecure?.call();
    _handshakeWatchdog?.cancel();

    // onAppPeerIdentified/onSecure가 이미 돌았으면(방 합류/재합류) conversationId가 방 id라서, 대화 전체가 아니라
    // 이 링크 상대(remotePeerId)의 멤버 슬롯에 SAS를 적음 (여러 멤버가 대화 하나를 공유해서 단일 sas 필드로는 구분 못 함)
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
        // 인바운드 소켓을 accept했으면 remotePort는 TCP accept가 본 피어의 아웃바운드 ephemeral 소스 포트일 뿐
        // 서버 리스닝 포트가 아님. hello가 진짜 리스닝 포트를 실어 오면 덮어써서 나중에 파일을 다시 밀 때 맞는 포트를 다이얼함
        peerPort: hello.port ?? c.peerPort,
        // 방이면 peerId를 안 건드림 (RoomMember가 멤버별로 들고 있고 대화 하나가 여러 링크에서 공유돼
        // 단일값으로 못 씀). 1:1이면 IP가 DHCP로 재할당돼도 재연결 때 "진짜 같은 피어인지" 확인할 수
        // 있게 기록 (_mergeDuplicateHost/connectToPeer 참고)
        peerId: isRoomLink ? null : hello.peerId,
      ),
    );
    _flushPending();
    unawaited(_sendOwedReceipts());
    if (stillVerified) unawaited(sendRawInnerOrClose(InnerFrame.verify()));
  }

  // 1:1에 이전 세션 코드가 남아 있으면 재연결. 재연결은 이 대화의 peerId(신원 키 해시)를 다시 증명해야
  // 이 대화로 이어지고(다이얼은 expectedPeerId, 인바운드는 _mergeDuplicateHost), 새 세션 키는 그 신원 키
  // 서명에 묶임: 전에 내가 코드를 확인한 신원 그대로면 그 확인이 이번 세션에도 맞아서 이어 감(true를 돌려
  // 상대에게 verify를 다시 보냄). 아니면 확인을 지우고 코드가 바뀐 이유를 알림
  // 상대 확인은 이번 세션에서 상대가 다시 알려야 켜짐 (상대가 대화를 지웠으면 꺼진 채로 남음)
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
