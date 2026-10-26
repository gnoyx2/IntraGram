part of '../link_registry.dart';

extension _RoomRoster on _LinkRegistryState {
  // 열린 멤버 링크. 같은 peerId 링크가 둘이면(재접속 직후) 최신 것만. 웹 게스트는 peerId가 없어 링크마다 한 명
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

  // 같은 멤버가 다시 붙으면 옛 링크를 닫음 (반쯤 죽은 링크가 인원을 부풀리고 경로를 붙들지 않게). 소켓 종료가 최대 2초라
  // 파일 경로는 닫기 전에 넘김. 그 peerId로 핸드셰이크를 통과하는 건 키 주인뿐이라 남이 멤버를 못 쫓아냄
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
