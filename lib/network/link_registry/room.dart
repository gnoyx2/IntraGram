part of '../link_registry.dart';

// 호스트 중계 방: 이 앱이 LAN 허브라 멤버 프레임을 다른 멤버에게 넘김. 중계하려고 풀어서 호스트는 방 평문을 봄.
// 확인은 멤버↔호스트 SAS뿐이고 방 전체 SAS는 없음. 웹 게스트 방과 앱 그룹 방은 다른 대화
mixin _LinkRegistryRoom on _LinkRegistryState {
  // 토큰을 통과한 웹 게스트 링크를 임시 대화에서 웹 게스트 방으로 옮김
  void _joinRoom(PeerLink link) {
    final roomId = _ensureWebGuestRoom();
    final guests = _roomLinks.where((l) => l.conversationId == roomId).length;
    if (guests >= kMaxWebGuests) {
      // 임시 대화를 지우고 닫음. 브라우저는 room_full을 보고 재시도 대신 '방이 꽉 찼어요'를 띄움
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
    // 이제 이 링크의 room_join·room_state는 다 거부됨 (호스트인 나를 멤버로 뒤집으려는 것 포함)
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
    // 게스트에게도 인원을 보냄: 브라우저는 이 첫 프레임을 입장 승인으로 봄 (토큰이 틀리면 아무것도 못 받고 닫혀서 'QR 다시 스캔'을 띄움)
    unawaited(link.sendRawInner(InnerFrame.roomState(count: count)));
  }

  // 증명된 앱 링크를 앱 그룹 방으로 옮김. 1:1에서 맞춘 확인은 같은 세션이라 이어 감
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

  // 열려 있는 1:1 앱 대화를 그 자리에서 앱 그룹 방으로 승격함 (기록 보존). 앱 그룹 방이 아직 없을 때만 실행함
  void _promoteToRoom(PeerLink link) {
    final id = link.conversationId;
    final priorTrust = store.conversation(id);
    _appRoomId = id;
    _links.remove(id);
    if (!_roomLinks.contains(link)) _roomLinks.add(link);
    link.onRoomFrame = (innerJson) => _relayRoomFrame(link, innerJson);
    link.markHostedMember();
    final peerId = link.remotePeerId;
    if (peerId != null) {
      store.upsertRoomMember(
        id,
        peerId,
        alias: link.peerAlias,
        platform: link.peerPlatform,
      );
      // 승격은 같은 링크·같은 세션이라 1:1에서 맞춘 확인을 그대로 이어 감
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

  // 멤버 프레임 중계: 텍스트 등은 방 전체로, 파일 협상은 대상별 경로로만 전달함 (바이트는 수신자가 보낸 멤버에게서 직접 당겨 옴)
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
    if (kind == 'msg' && from.transport == PeerTransport.app) {
      _broadcastRoomState(from.conversationId);
    }
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
