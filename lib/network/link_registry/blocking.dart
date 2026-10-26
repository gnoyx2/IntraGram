part of '../link_registry.dart';

// 기기 차단과 '내가 연 대화만 받기'. 신원 키가 실행마다 새로 생겨서 차단도 이번 실행 동안만 RAM에 둠
// (상대가 앱을 다시 켜면 새 ID라 닿음: 그걸 막는 게 '내가 연 대화만 받기'). 웹 게스트는 해당 없음
mixin _LinkRegistryBlocking on _LinkRegistryState {
  bool isBlocked(String peerId) => _blockedPeers.contains(peerId);

  // 1:1 상대만 (방은 호스트가 멤버를 관리)
  Future<void> blockPeer(String conversationId) async {
    final conversation = store.conversation(conversationId);
    final peerId = conversation?.peerId;
    if (conversation == null || conversation.isRoom || peerId == null) return;
    _blockedPeers.add(peerId);
    store.updateConversation(conversationId, (c) => c.copyWith(blocked: true));
    await _links[conversationId]?.close();
    store.addSystemMessage(
      conversationId,
      const SystemEvent(SystemEventKind.peerBlocked),
    );
  }

  void unblockPeer(String conversationId) {
    final peerId = store.conversation(conversationId)?.peerId;
    if (peerId == null) return;
    _blockedPeers.remove(peerId);
    store.updateConversation(conversationId, (c) => c.copyWith(blocked: false));
  }

  // 모르는 기기 = 이번 세션의 어느 대화·방 멤버에도 없는 peerId. 인바운드 거절 이유는 화면에 안 남아서 아무거나 씀
  @override
  SystemEventKind? _refusal(String peerId, {required bool dialledByUs}) {
    if (_blockedPeers.contains(peerId)) return SystemEventKind.peerBlocked;
    if (dialledByUs || !store.onlyChatsIStart) return null;
    final known = store.conversations.any(
      (c) => c.peerId == peerId || c.members.containsKey(peerId),
    );
    return known ? null : SystemEventKind.handshakeFailed;
  }
}
