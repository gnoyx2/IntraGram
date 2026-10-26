part of '../link_registry.dart';

extension _RoomRoster on _LinkRegistryState {
  // 열린 멤버 링크 목록임. 같은 peerId 링크가 둘이면(재접속 직후) 최신 것만 남김. 웹 게스트는 peerId가 없어 링크마다 한 명씩 셈
  List<PeerLink> _memberLinks(String roomId) {
    final open = _roomLinks
        .where((l) => l.conversationId == roomId && !l.isClosed)
        .toList();
    return <PeerLink>[
      for (var i = 0; i < open.length; i++)
        if (open[i].remotePeerId == null ||
            !open
                .skip(i + 1)
                .any((later) => later.remotePeerId == open[i].remotePeerId))
          open[i],
    ];
  }

  // 같은 멤버의 다른 열린 링크 (최신). 옛 링크가 늦게 닫혀도 나간 게 아님을 알아봄. 웹 게스트는 늘 null
  PeerLink? _sameMemberLink(PeerLink link) {
    final peerId = link.remotePeerId;
    if (peerId == null) return null;
    return _roomLinks.lastWhereOrNull(
      (other) =>
          !identical(other, link) &&
          other.conversationId == link.conversationId &&
          !other.isClosed &&
          other.remotePeerId == peerId,
    );
  }

  // 동일 멤버 재연결 시 이전 링크를 정리함 (비정상 링크의 인원 왜곡 및 경로 점유 방지). 소켓 종료에 최대 2초가 걸리므로
  // 파일 경로는 닫기 전에 인계함. 해당 peerId로 핸드셰이크를 통과하는 주체는 키 소유자뿐이라 타인이 멤버를 축출할 수 없음
  void _supersedeMemberLinks(PeerLink link) {
    final peerId = link.remotePeerId;
    if (peerId == null) return;
    final older = _roomLinks.where(
      (other) =>
          !identical(other, link) &&
          other.conversationId == link.conversationId &&
          !other.isClosed &&
          other.remotePeerId == peerId,
    );
    for (final old in older.toList()) {
      old.markSuperseded();
      _handOverRoomFileRoutes(old, link);
      unawaited(old.close());
    }
  }

  int _roomMemberCount(String roomId) => _memberLinks(roomId).length + 1;

  List<String>? _appRoomPeerIds(String roomId) {
    if (roomId != _appRoomId) return null;
    return <String>{
      identity.peerId,
      for (final link in _memberLinks(roomId))
        if (link.remotePeerId != null) link.remotePeerId!,
    }.toList(growable: false);
  }

  // 내가 호스트인 앱 방의 관측 장부 (범위는 처음에 무작위로 정함, 호스트는 나라서 작성자 서명이 이 방에 묶임)
  void _ensureRoomIntegrity(String roomId) {
    store.roomIntegrity.ensureRoom(roomId, host: identity.peerId);
    store.roomIntegrity.setMembers(roomId, _appRoomPeerIds(roomId) ?? const []);
  }

  Map<String, dynamic> _roomCheckpoint(String roomId) {
    if (roomId != _appRoomId) return const {};
    _ensureRoomIntegrity(roomId);
    return store.roomIntegrity.checkpoint(roomId);
  }

  Future<bool> _sendRoomJoin(PeerLink link, String roomId) =>
      link.sendRawInnerOrClose({
        ...InnerFrame.roomJoin(
          count: _roomMemberCount(roomId),
          peers: _appRoomPeerIds(roomId),
        ),
        ..._roomCheckpoint(roomId),
      });

  void _broadcastRoomState(
    String roomId, {
    PeerLink? except,
    String? joined,
    String? left,
  }) => unawaited(
    _broadcastToRoom(
      roomId,
      {
        ...InnerFrame.roomState(
          count: _roomMemberCount(roomId),
          joined: joined,
          left: left,
          peers: _appRoomPeerIds(roomId),
        ),
        ..._roomCheckpoint(roomId),
      },
      except: except,
      requiredDelivery: true,
    ),
  );
}
