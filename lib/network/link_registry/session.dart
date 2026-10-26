part of '../link_registry.dart';

mixin _LinkRegistrySession
    on
        _LinkRegistryState,
        _LinkRegistryRoom,
        _LinkRegistryFileWiring,
        _LinkRegistryDuplicates {
  // slot은 acceptInbound가 잡은 미인증 슬롯: 링크가 _links에 오르는 순간 풀어서 두 번 안 셈 (무산되면 호출부가 풂)
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
      // 이 await 동안 disposeAll이 돎: 늦은 세션·채널은 버림
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
    // onRoomFrame은 방 멤버 링크에만 연결함 (여기서 걸면 1:1 메시지가 방으로 샘)
    link.onClosed = _onLinkClosed;
    link.refusePeer = (peerId) =>
        _refusal(peerId, dialledByUs: link.dialledByUs);
    // 다이얼한 쪽은 connectToPeer가 이미 거름. 인바운드만 hello 뒤에 중복을 봄
    if (!dialledByUs) {
      link.onAppPeerIdentified = () => _mergeDuplicateHost(link);
    }
    _adoptLink(conversationId, link);
    slot?.release(); // 이제 _links에서 세어지니 예약은 풂
    await link.start();
  }

  // 링크가 못 된 채널을 닫음. 인바운드면 임시 대화도 지움 (다이얼한 쪽은 사용자가 누른 상대라 오프라인으로 둠)
  void _abandonRegistration(
    String conversationId,
    StreamChannel<dynamic> channel,
    bool dialledByUs,
  ) {
    unawaited(_closeAbandonedChannel(channel));
    if (!dialledByUs) store.wipeConversation(conversationId);
  }

  // 맵 값이 이 링크일 때만 지움 (대체된 옛 링크가 늦게 닫혀도 새 링크를 안 지움).
  // 일부러 sync: async면 store 정리·방 알림이 await 뒤로 밀려서 호출부가 갱신 전 값을 봄
  void _onLinkClosed(PeerLink link) {
    // 같은 멤버의 열린 링크가 남았으면(재접속 직후 옛 링크가 늦게 닫힘) 나간 게 아님: 경로만 넘기고 멤버 정리는 건너뜀
    final survivor = _sameMemberLink(link);
    _handOverRoomFileRoutes(link, survivor);
    if (identical(_links[link.conversationId], link)) {
      _links.remove(link.conversationId);
    }
    final roomId = link.conversationId;
    // 방 멤버였는지는 _roomLinks가 아니라 방 id로 봄: 같이 끊긴 링크는 먼저 정리된 쪽이 목록에서 뺐을 수 있어서,
    // 1:1 종료로 착각하면 다른 멤버 전송까지 다 버림
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
      // 앱 그룹 방 멤버 슬롯이면 offline으로 내리고 SAS·확인도 지움 (다시 들어오면 새로 채워짐)
      final leavingPeerId = link.remotePeerId;
      if (leavingPeerId != null) {
        store.setRoomMemberOffline(roomId, leavingPeerId);
      }
    }

    if (!_isRoomHub(roomId)) return;
    // 내 화면엔 나간 사람마다 한 줄, 알림은 한 번만 보냄 (room_state는 left가 하나뿐이라 동시에 나가면 마지막 한 명만 실림. count는 최신)
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
      // 링크 종료가 방을 offline으로 내렸지만 남은 멤버가 있으니 다시 올림
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

  // 내가 호스트인 방이면 멤버 링크를 전부 닫고 방 자리도 비움 (링크를 두면 숨은 중계가 계속되고 지운 방 id로 메시지가 다시 쌓임)
  Future<void> disconnect(String conversationId) async {
    store.roomIntegrity.remove(conversationId);
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
    // 첫 await 전에 세움: 이후 시작하거나 await 중이던 _register는 전부 걸림
    _disposed = true;
    store.roomIntegrity.clear();
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
    // 전송 정리가 실패해도(조각 파일 삭제 실패 등) 링크는 끝까지 닫고 실패는 마지막에 던짐
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
