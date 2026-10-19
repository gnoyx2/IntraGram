part of '../link_registry.dart';

// 호스트 중계 방(그룹): 링크를 1:1에서 공유 방으로 옮기기, 방 대화 만들기/재사용, 멤버 프레임 중계, 방 상태 브로드캐스트
// 브라우저 게스트도 앱 피어도 서버를 직접 못 써서 이 호스트 앱이 LAN 허브 역할. 웹 게스트 방(_webGuestRoomId)과
// 앱 그룹 방(_appRoomId)은 다른 대화 (웹 게스트가 앱 전용 방을 자동으로 보지 않게 분리)
// 호스트가 중계하려고 복호화하므로 호스트 기기는 방 평문을 봄. 멤버<->호스트 SAS로만 검증하고 방 전체 SAS는 없음
mixin _LinkRegistryRoom on _LinkRegistryState {
  // 웹 게스트 링크(토큰 검증 통과)를 임시 1:1 대화에서 공유 웹 게스트 방으로 옮김 (앱 피어는 _joinAppRoom)
  void _joinRoom(PeerLink link) {
    final roomId = _ensureWebGuestRoom();
    final guests = _roomLinks.where((l) => l.conversationId == roomId).length;
    if (guests >= kMaxWebGuests) {
      // 토큰 거절 경로처럼 임시 대화를 지우고 닫음. 브라우저는 room_full을 보고 재시도 대신 '방이 꽉 찼어요'를 띄움
      store.wipeConversation(link.conversationId);
      unawaited(
        link.deliverRawInner(InnerFrame.roomFull()).whenComplete(link.close),
      );
      return;
    }
    final provisional = link.conversationId;
    if (provisional != roomId) {
      _links.remove(provisional);
      store.wipeConversation(provisional);
      link.conversationId = roomId;
    }
    if (!_roomLinks.contains(link)) _roomLinks.add(link);
    link.onRoomFrame = (innerJson) => _relayRoomFrame(link, innerJson);
    // 이 링크는 이제 내가 호스팅하는 웹 게스트 방의 멤버: 이후 이 링크에서 오는 room_join/room_state는 전부 거부됨
    // (호스트인 나 자신을 멤버로 뒤집으려는 시도 포함)
    link.markWebGuest();
    final joiner = link.peerAlias;
    final count = _roomMemberCount(roomId);
    store.updateConversation(
      roomId,
      (c) => c.copyWith(
        online: true,
        isRoom: true,
        peerAlias: roomTitle(count),
        memberCount: count,
      ),
    );
    if (store.conversation(roomId) != null) {
      store.addSystemMessage(
        roomId,
        SystemEvent(SystemEventKind.memberJoined, joiner),
      );
    }
    _broadcastRoomState(roomId, except: link, joined: joiner);
    // 들어온 게스트에게도 지금 인원을 보냄: 브라우저는 이 첫 프레임을 입장 승인으로 보고 '온라인'을 띄움
    // (토큰이 틀리면 아무것도 안 받고 닫혀서 재시도 대신 'QR 다시 스캔'을 띄움)
    unawaited(link.sendRawInner(InnerFrame.roomState(count: count)));
  }

  // 이미 시큐어 세션이 있는 앱 피어 링크를 공유 앱 그룹 방으로 옮김.
  // 이전 1:1의 SAS/검증 상태를 이어감 (재연결이면 새 세션이라 없음)
  void _joinAppRoom(PeerLink link) {
    final roomId = _ensureAppRoom();
    final provisional = link.conversationId;
    final priorTrust = store.conversation(provisional);
    if (provisional != roomId) {
      _links.remove(provisional);
      store.wipeConversation(provisional);
      link.conversationId = roomId;
    }
    if (!_roomLinks.contains(link)) _roomLinks.add(link);
    link.onRoomFrame = (innerJson) => _relayRoomFrame(link, innerJson);
    // 이 링크는 이제 내가 호스팅하는 앱 그룹 방의 멤버
    link.markHostedMember();
    _supersedeMemberLinks(link);
    final peerId = link.remotePeerId;
    if (peerId != null) {
      store.upsertRoomMember(
        roomId,
        peerId,
        alias: link.peerAlias,
        platform: link.peerPlatform,
      );
      if (priorTrust?.localVerified ?? false) {
        store.setRoomMemberLocalVerified(roomId, peerId);
      }
      if (priorTrust?.peerVerified ?? false) {
        store.setRoomMemberPeerVerified(roomId, peerId);
      }
      final sas = link.sasDigits;
      if (sas != null) store.setRoomMemberSas(roomId, peerId, sas);
    }
    final joiner = link.peerAlias;
    final count = _roomMemberCount(roomId);
    store.updateConversation(
      roomId,
      (c) => c.copyWith(
        online: true,
        isRoom: true,
        peerAlias: roomTitle(count),
        memberCount: count,
      ),
    );
    if (store.conversation(roomId) != null) {
      store.addSystemMessage(
        roomId,
        SystemEvent(SystemEventKind.memberJoined, joiner),
      );
    }
    _broadcastRoomState(roomId, except: link, joined: joiner);
  }

  // 열려 있는 1:1 앱 대화를 그 자리에서 앱 그룹 방으로 승격 (기록 보존). 앱 그룹 방이 아직 없을 때만
  void _promoteToRoom(PeerLink link) {
    final id = link.conversationId;
    final priorTrust = store.conversation(id);
    _appRoomId = id;
    _links.remove(id);
    if (!_roomLinks.contains(link)) _roomLinks.add(link);
    link.onRoomFrame = (innerJson) => _relayRoomFrame(link, innerJson);
    // 이 링크는 이제 내가 호스팅하는 앱 그룹 방의 멤버
    link.markHostedMember();
    final peerId = link.remotePeerId;
    if (peerId != null) {
      store.upsertRoomMember(
        id,
        peerId,
        alias: link.peerAlias,
        platform: link.peerPlatform,
      );
      // 승격은 새 크립토 세션이 아니라 같은 링크를 그대로 씀(재연결과
      // 다름): 승격 전 1:1에서 이미 검증됐으면 신뢰를 초기화할 이유가
      // 없음
      if (priorTrust?.localVerified ?? false) {
        store.setRoomMemberLocalVerified(id, peerId);
      }
      if (priorTrust?.peerVerified ?? false) {
        store.setRoomMemberPeerVerified(id, peerId);
      }
      final sas = link.sasDigits;
      if (sas != null) store.setRoomMemberSas(id, peerId, sas);
    }
    store.updateConversation(
      id,
      (c) => c.copyWith(
        online: true,
        isRoom: true,
        peerAlias: roomTitle(2),
        memberCount: 2,
        // 1:1 자동 수락이 승격된 평문 방으로 안 이어지게 함
        autoAcceptFiles: false,
        localVerified: false,
        peerVerified: false,
      ),
    );
    store.addSystemMessage(id, const SystemEvent(SystemEventKind.becameRoom));
  }

  // 소각으로 대화가 사라졌으면 새로 만듦
  String _ensureWebGuestRoom() {
    final existing = _webGuestRoomId;
    if (existing != null && store.conversation(existing) != null) {
      return existing;
    }
    final id = newId();
    store.upsertConversation(
      Conversation(
        id: id,
        peerAlias: 'Room',
        peerPlatform: 'Room',
        transport: PeerTransport.web,
        startedAt: DateTime.now(),
        online: true,
        isRoom: true,
      ),
    );
    _webGuestRoomId = id;
    return id;
  }

  String _ensureAppRoom() {
    final existing = _appRoomId;
    if (existing != null && store.conversation(existing) != null) {
      return existing;
    }
    final id = newId();
    store.upsertConversation(
      Conversation(
        id: id,
        peerAlias: 'Room',
        peerPlatform: 'Room',
        transport: PeerTransport.app,
        startedAt: DateTime.now(),
        online: true,
        isRoom: true,
      ),
    );
    _appRoomId = id;
    return id;
  }

  // 한 멤버가 보낸 프레임을 같은 방의 다른 멤버 전원에게 중계: 텍스트 등은 방 전체에, 파일 협상은 대상별 등록 경로로만 보냄
  // (바이트는 호스트를 안 거치고 수신자가 원본 멤버에게 직접 당김)
  void _relayRoomFrame(PeerLink from, Map<String, dynamic> innerJson) {
    final kind = innerJson['k'];
    if (kind is String && kind.startsWith('file_')) {
      _relayRoomFileFrame(from, innerJson);
      return;
    }
    const relayable = <String>{
      'msg',
      'typing',
      'read',
      'burn',
      'react',
      'screenshot',
      'rename',
    };
    if (!relayable.contains(kind)) return;
    unawaited(
      _broadcastToRoom(
        from.conversationId,
        <String, dynamic>{...innerJson, 'from': from.peerAlias},
        except: from,
        requiredDelivery: kind != 'typing',
      ),
    );
  }
}
