part of '../link_registry.dart';

mixin _LinkRegistryConnect
    on _LinkRegistryState, _LinkRegistryRoom, _LinkRegistrySession {
  // 재사용 조건은 _existingLinkFor 참고. connectManual은
  // 진짜 peerId를 몰라 매번 새 임시값이라 남의/예전 대화를 가로채지 않음
  // verifyPeerId면 광고된 peerId(신원 키의 해시)를 가진 쪽임이
  // 증명될 때만 링크가 성립해서 가짜 광고로 연결/방 초대를 가로채지 못함
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
        // 다이얼로 기대한 상대(광고된 peerId, 증명은 링크가
        // 함): 이 대화의 재연결/인바운드 중복 합치기가 그 상대에게만
        // 묶이게
        // 수동 연결은 진짜 peerId를 몰라서 핸드셰이크 뒤에 채워짐
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

  // mDNS 멀티캐스트가 막힌 네트워크(카페/회사 Wi-Fi)용. 탐지된 피어와 같은
  // 경로를 타서 connectToPeer의 InternetAddress.tryParse
  // +
  // NetworkGuard.assertReachable이 소켓을 열기 전에 non-리터럴 호스트나 WAN 주소를 거부함
  // 기기 코드 QR처럼 화면에서 직접 읽은 peerId가 있으면 그 신원을 증명한 상대하고만 이어짐
  // 없으면(IP 직접 입력) 진짜 peerId를 몰라서 상대가 hello에서 밝힌 걸 그대로 받음
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
    // 미인증 연결 상한: 알 수 없는 피어가 hello를 안 보내는 소켓을 계속 열어 링크/타이머/대화 tile을 무한정 쌓는 걸 막음
    // 넘으면 store에 tile도 안 만들고 바로 닫음. host별 상한도 같이 걸어 한 기기가 슬롯을 독식 못 하게 함
    // 검사와 슬롯 예약은 첫 await 전에 같은 동기 구간에서 함: 세션을 만드는 동안은 이 접속이 아직 _links에 없어서,
    // 예약 안 하면 한꺼번에 들어온 접속이 전부 검사를 통과해 상한을 넘음
    final slot = _disposed ? null : _admitInbound(remoteHost);
    if (slot == null) {
      await _closeAbandonedChannel(channel);
      return;
    }
    try {
      // 이 시점엔 앱 피어인지 브라우저 게스트인지 몰라서 host로 dedupe
      // 못 함: 같은 host에 여러 브라우저 게스트가 동시에 붙는 건
      // 정상(한 호스트에서 각자 다른 탭)이라 합치면 게스트가 서로를 밀어냄
      // 앱 피어 재연결 중복은 hello로 정체가 밝혀진 뒤 _mergeDuplicateHost에서 처리
      final conversationId = newId();
      store.upsertConversation(
        Conversation(
          id: conversationId,
          // hello 전 임시 이름은 언어와 무관한 주소 (hello가 진짜 이름으로 바꿈)
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
      slot.release(); // 링크가 못 되고 나가는 모든 출구(던짐 포함)에서 반환. 이미 풀렸으면 무시
    }
  }

  // 이미 그 피어와 증명된 1:1 링크가 있으면 그걸 승격/합류시키고, 없으면(다이얼
  // 중인 링크 포함) secure 되면 방에 넣음 증명 전 링크는 방에 안 넣음
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

  // 다이얼 실패는 이유(PeerUnreachableReason)를 담아 올림. 사설 주소가 아니면 SecurityException 그대로
  Future<StreamChannel<dynamic>> _dialPeer(PeerDevice peer) async {
    try {
      final dial = _debugDial; // 테스트 seam: 프로덕션에선 항상 null
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

  // 끊긴 대화를 마지막 알려진 주소로 다시 다이얼: 기록/설정은 두고 conversationId를 재사용하며 크립토 세션만 새로 맺음
  // 링크가 이미 있거나 주소를 모르면 조용히 무시 (오프라인 배너가 오프라인으로 보여주는 게 정직한 신호)
  // 다이얼이 실패하면 PeerUnreachableException/SecurityException을 올림
  Future<void> reconnect(String conversationId) async {
    final existing = _links[conversationId];
    if (existing != null && !existing.isClosed) return;

    final conversation = store.conversation(conversationId);
    final host = conversation?.peerHost;
    final port = conversation?.peerPort;
    if (conversation == null || host == null || port == null) return;

    // 재연결은 새 암호 세션(= 새 SAS): 상대 확인은 이 세션에서 다시 받아야 해서 먼저 지움. 내 확인은
    // 같은 신원 키를 다시 증명했을 때만 핸드셰이크 끝에서 이어짐 (PeerLink._carryVerification)
    store.updateConversation(
      conversationId,
      (c) => c.copyWith(peerVerified: false),
    );

    // 소켓에서 막히면 이유를 올려 오프라인 배너가 안내하게 함 (조용히 원상복귀하지 않음)
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
      // DHCP 재할당 등으로 이 주소에 다른 기기가 있으면 hello의
      // peerId가 달라서 링크를 닫음 (이 대화에 조용히 안 이어붙임)
      // peerId가 없는 건 핸드셰이크를 끝낸 적 없는 수동 IP 대화뿐이고(탐지된
      // 피어 다이얼은 기대한 peerId를 적어 둠) 그때만 검사 안 함
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

  // connectToPeer/inviteToRoom이 공유하는 lookup: 그 peerId를 증명한
  // secure 링크, 또는 그 peerId를 기대하며 우리가 다이얼해 둔(증명 전) 링크만 재사용
  // host만 보면 안 됨: 같은 주소에서 미리 열어 둔 미인증 인바운드 소켓(공격자)이나 DHCP로 주소를 넘겨받은 다른 기기가
  // 사용자가 누른 상대 자리를 차지해 기대한 peerId 검사를 건너뜀
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
