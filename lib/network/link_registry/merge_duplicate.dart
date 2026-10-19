part of '../link_registry.dart';

// 인바운드 링크가 앱 피어 hello로 정체를 밝힌 뒤의 중복 정리
// 방 헬퍼(_joinAppRoom)가 필요해서 _LinkRegistryRoom 위에 얹음
mixin _LinkRegistryDuplicates on _LinkRegistryState, _LinkRegistryRoom {
  // 같은 host의 기존 1:1 대화가 남아있으면(피어 재연결) 방금 만든 throwaway
  // 대화를 버리고 그 대화로 옮겨 탐 (같은 기기가 두 줄로 뜨던 문제 방지)
  // 새 크립토 세션이라 검증은 이 직후 PeerLink._carryVerification이 정함 (같은 신원 키면 내 확인만 이어짐)
  // host만 보고 합치면 위험함 (DHCP로 같은 IP를 받은 다른 기기가 합쳐짐):
  // 대화의 peerId가 이번 링크가 증명한 peerId와 같을 때만 합침
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
        // 그 자리에 살아있던 옛 링크(예: 아직 핸드셰이크 중이던 중복 연결): markSuperseded는
        // _adoptLink가 이미 했으니 실제로 닫아서 소켓/구독도 정리
        unawaited(stale.close());
      }
      store.updateConversation(dup.id, (c) => c.copyWith(peerId: linkPeerId));
      return;
    }
    // host 매칭 1:1이 없으면 내 앱 그룹 방(_appRoomId)의 예전 멤버가 재연결한
    // 건지 peerId로 봄 (방은 host-IP로 dedupe 못 함, connect.dart
    // 참고)
    // 맞으면 _joinAppRoom으로 재합류시킴 (안 그러면 그 멤버 슬롯이 고아 1:1로 새고 방으로 영영 안 돌아옴)
    final roomId = _appRoomId;
    final peerId = link.remotePeerId;
    if (roomId != null &&
        peerId != null &&
        (store.conversation(roomId)?.members.containsKey(peerId) ?? false)) {
      _joinAppRoom(link);
      // 끊긴 동안 다른 멤버가 오갔을 수 있어서 복귀한 멤버에게 최신
      // 인원수를 바로 알려줌 (inviteToRoom의 첫 합류 흐름과
      // 같은 패턴)
      unawaited(_sendRoomJoin(link, roomId));
    }
  }
}
