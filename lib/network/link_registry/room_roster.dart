part of '../link_registry.dart';

extension _RoomRoster on _LinkRegistryState {
  // 같은 앱 멤버(peerId)의 링크가 둘이면(재접속 직후 옛 링크가 아직 안
  // 닫힘) 가장 최근 것 하나만. 브라우저 게스트는 peerId가 없어 링크마다
  // 한 명
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

  // 같은 앱 멤버의 방에 남은 다른 열린 링크(가장 최근 것): 옛 링크가 뒤늦게 닫혀도 그 멤버가 나간 게 아님을 알아보는 용도
  // 웹 게스트는 peerId가 없어 항상 null
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

  // 같은 앱 멤버(인증된 peerId)가 다시 붙었으면 옛 링크를 닫음 (반쯤 죽은 옛 링크가 멤버 수를
  // 부풀리고 경로를 붙들지 않게). markSuperseded로 방 상태/"연결 끊김" 줄은 안 건드림
  // 파일 경로는 닫기 전에 이 링크로 동기적으로 넘김: 소켓 종료가 최대 2초
  // 걸려서 그 사이 이 링크의 accept/ACK가 "닫힌 경로"로 버려지면 안
  // 됨
  // 그 peerId로 핸드셰이크를 통과할 수 있는 쪽은 키를 가진 그 멤버뿐이라 남이 멤버를 쫓아낼 수 없음
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

  Future<void> _sendRoomJoin(PeerLink link, String roomId) => link.sendRoomJoin(
    _roomMemberCount(roomId),
    peers: _appRoomPeerIds(roomId),
  );

  void _broadcastRoomState(
    String roomId, {
    PeerLink? except,
    String? joined,
    String? left,
  }) => unawaited(
    _broadcastToRoom(
      roomId,
      InnerFrame.roomState(
        count: _roomMemberCount(roomId),
        joined: joined,
        left: left,
        peers: _appRoomPeerIds(roomId),
      ),
      except: except,
      requiredDelivery: true,
    ),
  );
}
