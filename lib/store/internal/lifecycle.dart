part of '../in_memory_store.dart';

mixin _StoreLifecycle on _InMemoryStoreState, _StoreCore {
  void wipeConversation(String conversationId) {
    _typingTimers.remove(conversationId)?.cancel();
    for (final m
        in _messages[conversationId]?.values ?? const <EphemeralMessage>[]) {
      _messageRooms.remove(m.id);
      _burnTimers.remove(m.id)?.cancel();
      _ceilingTimers.remove(m.id)?.cancel();
    }
    _messages.remove(conversationId);
    _conversations.remove(conversationId);
    _owedReads.remove(conversationId);
    _owedBurns.remove(conversationId);
    // 맵을 도는 동시에 지우면 ConcurrentModificationError라 id부터 뽑음
    // 개별 _removeTransfer를 거쳐야 owned voiceBytes
    // wipe와 네트워크 정리가 전송마다 실행됨 (removeWhere는 참조만 뗌)
    final transferIds = _transfers.values
        .where((t) => t.conversationId == conversationId)
        .map((t) => t.id)
        .toList();
    for (final id in transferIds) {
      _removeTransfer(id);
    }
    final controller = _roomEvents.remove(conversationId);
    controller?.add(const <EphemeralMessage>[]);
    controller?.close();
    _emitConversations();
    _emitTransfers();
  }

  // 모든 타이머 취소, 컬렉션 비움, 리스너에 빈 결과 통보. 이후에도 스토어는 계속 씀 (새로운 빈 세션)
  // 메시지 String은 참조만 끊음(덮을 수 없음). 전송 바이트 버퍼는 _removeTransfer가 덮음
  // 전송은 _removeTransfer를 하나씩 거침. 끝까지 기다리려면 drainDisposals를 쓸 것 (패닉 경로가 그럼)
  void secureWipe() {
    for (final timer in _burnTimers.values) {
      timer.cancel();
    }
    _burnTimers.clear();
    for (final timer in _ceilingTimers.values) {
      timer.cancel();
    }
    _ceilingTimers.clear();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();

    final rooms = _messages.keys.toList();
    _messages.clear();
    _messageRooms.clear();
    _conversations.clear();
    _owedReads.clear();
    _owedBurns.clear();
    for (final id in _transfers.keys.toList()) {
      _removeTransfer(id);
    }

    for (final room in rooms) {
      final controller = _roomEvents[room];
      controller?.add(const <EphemeralMessage>[]);
    }
    _emitConversations();
    _emitTransfers();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _saveMaxWait?.cancel();
    _saveMaxWait = null;
    secureWipe();
    for (final controller in _roomEvents.values) {
      controller.close();
    }
    _roomEvents.clear();
    _conversationEvents.close();
    _transferEvents.close();
    _localBurns.close();
    _inboundActivity.close();
  }
}
