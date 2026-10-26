part of '../link_registry.dart';

mixin _LinkRegistryConnect
    on _LinkRegistryState, _LinkRegistryRoom, _LinkRegistrySession {
  // verifyPeerId면 광고된 peerId(신원 키 해시)의 주인임이 증명돼야 링크가 섬: 가짜 광고로 연결·방 초대를 못 가로챔
  Future<String> connectToPeer(
    PeerDevice peer, {
    bool verifyPeerId = true,
  }) async {
    final existing = _existingLinkFor(peer);
    if (existing != null) return existing.key;

    final channel = await _dialPeer(peer);

    final conversationId = newId();
    store.upsertConversation(
      Conversation(
        id: conversationId,
        peerAlias: peer.alias,
        peerPlatform: peer.platform,
        transport: PeerTransport.app,
        startedAt: DateTime.now(),
        peerHost: peer.host,
        peerPort: peer.port,
        // 재연결·중복 합치기가 이 상대에게만 묶이게 기대한 peerId를 적음. 수동 연결은 몰라서 핸드셰이크 뒤에 채움
        peerId: verifyPeerId ? peer.peerId : null,
        online: false,
      ),
    );

    await _register(
      conversationId: conversationId,
      channel: channel,
      remoteHost: peer.host,
      remotePort: peer.port,
      dialledByUs: true,
      expectedPeerId: verifyPeerId ? peer.peerId : null,
    );
    return conversationId;
  }

  // mDNS가 막힌 망(카페·회사 Wi-Fi)용. 다이얼 경로가 같아서 리터럴 사설 IP만 통과함.
  // QR로 읽은 peerId가 있으면 그 신원을 증명한 상대하고만 이어지고, IP만 치면 상대가 hello에서 밝힌 걸 받음
  Future<String> connectManual({
    required String host,
    required int port,
    String? expectedPeerId,
  }) {
    return connectToPeer(
      PeerDevice(
        peerId: expectedPeerId ?? newId(),
        alias: host,
        platform: 'Unknown',
        host: host,
        port: port,
        seenAt: DateTime.now(),
      ),
      verifyPeerId: expectedPeerId != null,
    );
  }

  Future<void> acceptInbound(
    StreamChannel<dynamic> channel, {
    required String remoteHost,
    int? remotePort,
    String? Function()? requiredWebToken,
  }) async {
    // 미인증 상한: hello 없는 소켓을 계속 열어 링크·타이머·대화 칸을 쌓는 걸 막음 (넘으면 칸도 안 만들고 닫음).
    // 검사와 예약은 첫 await 전에: 세션 만드는 동안은 _links에 없어서 안 그러면 몰려온 접속이 다 통과함
    final slot = _disposed ? null : _admitInbound(remoteHost);
    if (slot == null) {
      await _closeAbandonedChannel(channel);
      return;
    }
    try {
      // 아직 앱인지 브라우저인지 몰라서 host로 못 합침 (한 PC의 탭 여럿은 정상). 앱 재연결 중복은 hello 뒤 _mergeDuplicateHost가 처리
      final conversationId = newId();
      store.upsertConversation(
        Conversation(
          id: conversationId,
          // hello 전 임시 이름은 언어 상관없는 주소
          peerAlias: remoteHost,
          peerPlatform: 'Unknown',
          transport: PeerTransport.app,
          startedAt: DateTime.now(),
          peerHost: remoteHost,
          peerPort: remotePort,
          online: true,
        ),
      );
      await _register(
        conversationId: conversationId,
        channel: channel,
        remoteHost: remoteHost,
        remotePort: remotePort,
        dialledByUs: false,
        requiredWebToken: requiredWebToken,
        slot: slot,
      );
    } finally {
      slot.release(); // 던짐 포함 모든 출구에서 반환 (이미 풀렸으면 무시)
    }
  }

  // 증명된 링크가 있으면 바로 방에 넣고, 없으면 다이얼해서 증명이 끝난 뒤에 넣음
  Future<void> inviteToRoom(PeerDevice peer) async {
    final existing = _existingLinkFor(peer);
    if (existing != null && existing.value.isSecure) {
      final link = existing.value;
      _joinAppRoom(link);
      await _sendRoomJoin(link, _appRoomId!);
      return;
    }
    final epoch = _appRoomEpoch;
    final conversationId = await connectToPeer(peer);
    final link = _links[conversationId];
    if (link == null) return;
    void enter() {
      // 증명을 기다리는 사이 방이 끝났으면 1:1 대화로만 남김
      if (epoch != _appRoomEpoch) return;
      _joinAppRoom(link);
      _sendRoomJoin(link, _appRoomId!);
    }

    if (link.isSecure) {
      enter();
    } else {
      link.onSecure = enter;
    }
  }

  // 다이얼 실패는 이유를 담아 올림. 사설 주소가 아니면 SecurityException 그대로
  Future<StreamChannel<dynamic>> _dialPeer(PeerDevice peer) async {
    try {
      final dial = _debugDial;
      return dial != null
          ? await dial(peer)
          : await _dialPeerSocket(
              peer.host,
              peer.port,
              mode: () => store.largeMessageMode,
            );
    } on Exception catch (e) {
      if (e is SecurityException) rethrow;
      throw PeerUnreachableException('$e', reason: classifyDialError(e));
    }
  }

  // 끊긴 대화를 마지막 주소로 다시 다이얼: 기록·설정은 두고 암호 세션만 새로. 링크가 있거나 주소를 모르면 그냥 둠
  Future<void> reconnect(String conversationId) async {
    final existing = _links[conversationId];
    if (existing != null && !existing.isClosed) return;

    final conversation = store.conversation(conversationId);
    // 내가 연 방은 다시 걸 상대가 하나가 아님 (멤버가 각자 다시 들어옴). 1:1에서 승격된 방은 옛 상대 주소를 들고 있어서
    // 걸면 그 링크가 방 자리에 끼어들어 멤버 코드 확인·방 파일이 엉뚱한 기기로 감
    if (conversation != null &&
        conversation.isRoom &&
        conversation.hostAlias == null) {
      return;
    }
    final host = conversation?.peerHost;
    final port = conversation?.peerPort;
    if (conversation == null || host == null || port == null) return;

    // 새 세션 = 새 SAS라 상대 확인은 다시 받아야 함. 내 확인은 같은 신원 키를 다시 증명하면 핸드셰이크 끝에서 이어짐
    store.updateConversation(
      conversationId,
      (c) => c.copyWith(peerVerified: false),
    );

    final channel = await _dialPeer(
      PeerDevice(
        peerId: conversation.peerId ?? '',
        alias: conversation.peerAlias,
        platform: conversation.peerPlatform,
        host: host,
        port: port,
        seenAt: DateTime.now(),
      ),
    );

    await _register(
      conversationId: conversationId,
      channel: channel,
      remoteHost: host,
      remotePort: port,
      dialledByUs: true,
      // DHCP로 딴 기기가 이 주소를 받았으면 peerId가 달라서 닫힘. null은 핸드셰이크를 못 마친 수동 IP 대화뿐
      expectedPeerId: conversation.peerId,
    );
  }

  // 방이 없으면 이 대화를 그 자리에서 방으로 승격 (기록 보존)
  Future<void> addPeersToRoom(
    String fromConversationId,
    List<PeerDevice> peers,
  ) async {
    final link = _links[fromConversationId];
    if (link != null && link.isSecure) {
      if (_appRoomId == null) {
        _promoteToRoom(link);
      } else {
        _joinAppRoom(link);
      }
      await _sendRoomJoin(link, _appRoomId!);
    }
    for (final peer in peers) {
      await inviteToRoom(peer);
    }
  }

  // 그 peerId를 증명한 링크나, 그 peerId를 기대하고 우리가 다이얼한 링크만 다시 씀. host만 보면 같은 주소에서
  // 미리 열어 둔 미인증 소켓이나 DHCP로 주소를 받은 딴 기기가 그 자리를 차지해서 peerId 검사를 건너뜀
  MapEntry<String, PeerLink>? _existingLinkFor(PeerDevice peer) =>
      _links.entries.firstWhereOrNull((e) {
        final link = e.value;
        return !link.isClosed &&
            store.conversation(e.key)?.peerHost == peer.host &&
            (link.isSecure
                ? link.remotePeerId == peer.peerId
                : link.dialledByUs && link.expectedPeerId == peer.peerId);
      });
}
