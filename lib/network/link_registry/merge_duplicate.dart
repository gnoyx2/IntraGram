part of '../link_registry.dart';

// 인바운드 링크가 hello로 정체를 밝힌 뒤의 중복 정리
mixin _LinkRegistryDuplicates on _LinkRegistryState, _LinkRegistryRoom {
  // 같은 상대의 1:1이 남아 있으면(재연결) 임시 대화를 버리고 그리로 옮겨 탐 (한 기기가 두 줄로 안 뜨게).
  // host만 보면 DHCP로 같은 IP를 받은 딴 기기가 합쳐져서 증명된 peerId까지 같아야 함
  void _mergeDuplicateHost(PeerLink link) {
    final provisional = link.conversationId;
    final host = link.remoteHost;
    final linkPeerId = link.remotePeerId;
    if (host == null || linkPeerId == null) return;
    final dup = store.conversations.firstWhereOrNull(
      (c) =>
          c.id != provisional &&
          c.peerHost == host &&
          !c.isRoom &&
          c.peerId == linkPeerId,
    );
    if (dup != null) {
      _links.remove(provisional);
      store.wipeConversation(provisional);
      final stale = _links[dup.id];
      link.conversationId = dup.id;
      _adoptLink(dup.id, link);
      if (stale != null && !identical(stale, link)) {
        // 그 자리의 옛 링크는 _adoptLink가 이미 대체 표시함. 실제로 닫아서 소켓까지 정리
        unawaited(stale.close());
      }
      store.updateConversation(dup.id, (c) => c.copyWith(peerId: linkPeerId));
      return;
    }
    // 1:1이 없으면 내 앱 그룹 방 멤버가 다시 붙은 건지 봄. 맞으면 방으로 되돌림 (안 그러면 따로 노는 1:1이 됨)
    final roomId = _appRoomId;
    final peerId = link.remotePeerId;
    if (roomId != null &&
        peerId != null &&
        (store.conversation(roomId)?.members.containsKey(peerId) ?? false)) {
      _joinAppRoom(link);
      // 끊긴 사이 인원이 바뀌었을 수 있어서 바로 알려 줌
      unawaited(_sendRoomJoin(link, roomId));
    }
  }
}
