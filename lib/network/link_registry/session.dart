part of '../link_registry.dart';

mixin _LinkRegistrySession
    on
        _LinkRegistryState,
        _LinkRegistryRoom,
        _LinkRegistryFileWiring,
        _LinkRegistryDuplicates {
  // slot은 acceptInbound가 첫 await 전에 잡은 미인증
  // 슬롯: 링크가 _links에 오르는 자리에서 풀어 두 번 세지 않음
  // 세션 생성이 던지거나 dispose 경합으로 등록이 무산되는 출구에선 호출부가 풀고, 링크가 못 된 채널과
  // 인바운드의 임시 대화는 _abandonRegistration에서 정리
  Future<void> _register({
    required String conversationId,
    required StreamChannel<dynamic> channel,
    required String remoteHost,
    required int? remotePort,
    required bool dialledByUs,
    String? expectedPeerId,
    String? Function()? requiredWebToken,
    _InboundSlot? slot,
  }) async {
    if (_disposed) {
      _abandonRegistration(conversationId, channel, dialledByUs);
      return;
    }
    final generation = _generation;
    final CryptoSession session;
    try {
      session = await (_debugCreateSession?.call() ?? crypto.createSession());
    } on Object {
      _abandonRegistration(conversationId, channel, dialledByUs);
      rethrow;
    }
    if (_disposed || generation != _generation) {
      // disposeAll이 이 await 도는 동안 돎: 늦게 얻은 세션/채널은 store에 안 올리고 바로 버림
      session.destroy();
      _abandonRegistration(conversationId, channel, dialledByUs);
      return;
    }
    final link = PeerLink(
      conversationId: conversationId,
      channel: channel,
      store: store,
      identity: identity,
      crypto: session,
      remoteHost: remoteHost,
      remotePort: remotePort,
      localPort: localEndpoint?.port,
      dialledByUs: dialledByUs,
      expectedPeerId: expectedPeerId,
      requiredWebToken: requiredWebToken,
    );
    _wireFileCallbacks(link);
    link.onAutoAcceptOffer = (transferId) {
      unawaited(_transfers.incoming.accept(transferId));
    };
    link.onWebGuestHello = () => _joinRoom(link);
    // onRoomFrame은 방 멤버 링크에만 세팅 (_joinRoom/_promoteToRoom에서).
    // 1:1 링크에 세팅하면 1:1 메시지가 방으로 새므로 여기선 안 함
    link.onClosed = _onLinkClosed;
    link.refusePeer = (peerId) =>
        _refusal(peerId, dialledByUs: link.dialledByUs);
    // 다이얼한 쪽은 connectToPeer가 다이얼 전에 이미 host로
    // dedupe함. 인바운드만 hello로 정체가 밝혀진 뒤 중복 체크가
    // 필요
    if (!dialledByUs) {
      link.onAppPeerIdentified = () => _mergeDuplicateHost(link);
    }
    _adoptLink(conversationId, link);
    slot?.release(); // 이제 _links의 미인증 링크로 세어지니 예약을 풀어 이중 집계 방지
    await link.start();
  }

  // 링크가 못 된 채널을 닫음. 인바운드면 acceptInbound가 만든 임시 "peer" 대화도 지워 유령 tile이 안 남게 함
  // (다이얼한 쪽 대화는 사용자가 누른 상대의 오프라인 tile이라 둠)
  void _abandonRegistration(
    String conversationId,
    StreamChannel<dynamic> channel,
    bool dialledByUs,
  ) {
    unawaited(_closeAbandonedChannel(channel));
    if (!dialledByUs) store.wipeConversation(conversationId);
  }

  // link 자신을 받아서 현재 맵 값과 identical일 때만 제거: 대체된 옛 링크의 뒤늦은 종료가 새 링크를 지우지 않게 함
  // 일부러 sync: onClosed가 void Function이라 아무도 반환값을 안 기다리고,
  // async로 바꾸면 store 정리/방 브로드캐스트가 첫 await 뒤로 밀려 테스트/호출부가
  // 갱신 전 값을 봄. 전송 정리는 handleLinkClosed가 내부에서 await
  void _onLinkClosed(PeerLink link) {
    // 같은 멤버의 다른 열린 링크가 방에 남았으면(재접속 직후 옛 링크가 뒤늦게 닫힘) 나간 게 아님: 경로를 그 링크로 넘기고
    // 멤버 정리(오프라인/퇴장 알림/전송 실패)는 건너뜀. 없으면 경로를 지움
    final survivor = _sameMemberLink(link);
    _handOverRoomFileRoutes(link, survivor);
    if (identical(_links[link.conversationId], link)) {
      _links.remove(link.conversationId);
    }
    final roomId = link.conversationId;
    // 방 멤버 링크였으면 그 멤버의 전송 상태만 정리함. 소속은 _roomLinks가
    // 아니라 방 id로 판단: 한 틱에 같이 끊긴 링크는 먼저 끝난 링크의 정리가
    // 이미 목록에서 뺐을 수 있는데, 그걸 1:1 종료로 오해하면 방의 다른 멤버 전송까지 통째로 버림
    final wasRoomLink = _isRoomHub(roomId);
    final leftAliases = _roomLinks
        .where(
          (roomLink) =>
              roomLink.conversationId == roomId &&
              roomLink.isClosed &&
              _sameMemberLink(roomLink) == null,
        )
        .map((roomLink) => roomLink.peerAlias)
        .toList();
    _roomLinks.removeWhere((roomLink) => roomLink.isClosed);
    if (survivor == null) {
      unawaited(
        _transfers.handleLinkClosed(
          roomId,
          peerKey: wasRoomLink ? recipientKeyOf(link) : null,
        ),
      );
      // 방 멤버 슬롯이 있으면(앱 그룹 방만, 웹 게스트는 멤버 슬롯 없음) online=false + SAS/검증 초기화
      // 재합류하면 upsertRoomMember가 새 인스턴스로 덮어써서 되돌아옴
      final leavingPeerId = link.remotePeerId;
      if (leavingPeerId != null) {
        store.setRoomMemberOffline(roomId, leavingPeerId);
      }
    }

    if (!_isRoomHub(roomId)) return;
    // 로컬 시스템 메시지는 나간 사람마다 한 줄씩, 원격 브로드캐스트는 루프 밖에서
    // 한 번만 (여러 멤버가 한 틱에 끊기면 불안정한 남은 소켓에 N번 쓰게 됨)
    // _broadcastRoomState는 프로토콜상 left 한 명분만 실어서 동시 이탈이면
    // 마지막 한 명만 원격 알림에 실리지만 로컬 메시지는 전원 보여 정보 손실은 없고 count는
    // 최신값
    for (final alias in leftAliases) {
      if (store.conversation(roomId) != null) {
        store.addSystemMessage(
          roomId,
          SystemEvent(SystemEventKind.memberLeft, alias),
        );
      }
    }
    if (leftAliases.isNotEmpty) {
      _broadcastRoomState(roomId, left: leftAliases.last);
    }
    final stillHasMembers = _roomLinks.any(
      (roomLink) => roomLink.conversationId == roomId,
    );
    if (!stillHasMembers) {
      store.setConversationOnline(roomId, online: false);
    } else {
      // 링크가 닫히면서 PeerLink._shutdown이 방을 offline으로
      // 돌려놨는데 아직 다른 멤버가 남았으니 다시 online으로 올리고 라벨/인원을
      // 갱신
      final count = _roomMemberCount(roomId);
      store.updateConversation(
        roomId,
        (c) => c.copyWith(
          online: true,
          peerAlias: roomTitle(count),
          memberCount: count,
        ),
      );
    }
  }

  // 1:1이면 그 링크를, 내가 호스트인 방이면 그 방의 멤버 링크 전부를 닫고 방 자리도 비움
  // (방 대화만 지우고 링크를 두면 기기가 숨은 중계를 계속하고, 그 뒤 메시지가 지운 방 id로 다시 쌓임)
  Future<void> disconnect(String conversationId) async {
    if (_isRoomHub(conversationId)) {
      if (conversationId == _appRoomId) {
        _appRoomId = null;
        _appRoomEpoch++;
      }
      if (conversationId == _webGuestRoomId) _webGuestRoomId = null;
      final members = _roomLinks
          .where((link) => link.conversationId == conversationId)
          .toList();
      for (final link in members) {
        await link.close();
      }
    }
    await _links[conversationId]?.close();
  }

  Future<void> disposeAll() async {
    // 첫 await 전에 동기적으로 닫음: 이 시점 이후 시작되는(또는 이미
    // await 중이던) _register는 전부 자기 admission 검사에서
    // 걸림
    _disposed = true;
    _roomFileRoutes.clear();
    _inboundAccepts.clear(); // 접속했던 기기 주소를 RAM에 남기지 않음
    _generation++;
    await _localBurnSub?.cancel();
    _localBurnSub = null;
    final links = <PeerLink>[..._links.values, ..._roomLinks];
    _links.clear();
    _roomLinks.clear();
    _webGuestRoomId = null;
    _appRoomId = null;
    // 전송 정리가 실패해도(파셜 삭제 실패 등) 링크는 끝까지 닫고 실패는 마지막에 그대로 던짐:
    // 실패를 성공처럼 삼키지도, 일부 링크를 열어둔 채 멈추지도 않음
    Object? transferError;
    StackTrace? transferStack;
    try {
      await _transfers.dispose();
    } on Object catch (e, st) {
      transferError = e;
      transferStack = st;
    }
    for (final link in links) {
      await link.close();
    }
    if (transferError != null) {
      Error.throwWithStackTrace(transferError, transferStack!);
    }
  }
}
