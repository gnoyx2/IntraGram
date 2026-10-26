part of '../in_memory_store.dart';

mixin _StoreLifecycle on _InMemoryStoreState, _StoreCore {
  void wipeConversation(String conversationId) {
    final generation = evidence.generation;
    roomIntegrity.remove(conversationId);
    _typingTimers.remove(conversationId)?.cancel();
    // 정리 증적이 묶을 대상: 지우기 전에 메시지 id만 뽑음, 본문은 안 읽음 (안내 줄뿐인 임시 대화는 증적을 안 남김)
    final wipedMessageIds = <String>[];
    for (final m
        in _messages[conversationId]?.values ?? const <EphemeralMessage>[]) {
      if (m.kind != MessageKind.system) wipedMessageIds.add(m.id);
      _messageRooms.remove(m.id);
      _burnTimers.remove(m.id)?.cancel();
      _ceilingTimers.remove(m.id)?.cancel();
    }
    _messages.remove(conversationId);
    _conversations.remove(conversationId);
    _owedReads.remove(conversationId);
    _owedBurns.remove(conversationId);
    // _removeTransfer를 하나씩 거쳐야 음성 바이트 덮기와 네트워크 정리가 돎 (도는 중에 지우면 안 돼서 id부터 뽑음)
    final transferIds = _transfers.values
        .where((t) => t.conversationId == conversationId)
        .map((t) => t.id)
        .toList();
    // 전송마다 따로 말고 대화 하나로 정리 증적을 남김 (다 정리돼야 completed)
    final disposals = <Future<void>>[
      for (final id in transferIds) _removeTransfer(id, attest: false),
    ];
    if (wipedMessageIds.isNotEmpty || transferIds.isNotEmpty) {
      _attestCleanup(
        this,
        done: Future.wait(disposals),
        subjectId: conversationId,
        conversationId: conversationId,
        policy: 'cleanup/conversation',
        sinceGeneration: generation,
        fields: <Object?>[
          conversationId,
          (wipedMessageIds..sort()).join(','),
          (transferIds..sort()).join(','),
        ],
      );
    }
    final controller = _roomEvents.remove(conversationId);
    controller?.add(const <EphemeralMessage>[]);
    controller?.close();
    _emitConversations();
    _emitTransfers();
  }

  // 다 비우고 빈 결과를 알림. 스토어는 계속 씀 (빈 새 세션). 정리가 끝나길 기다리려면 drainDisposals.
  // Panic 진입 때 동결·소거한 장부도 다시 비움: 종료 중 파생된 잔여물이 새 세션에 남지 않게 함.
  void secureWipe() {
    evidence.clear();
    roomIntegrity.clear();
    orgCredentials.clear();
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
      _removeTransfer(id, attest: false);
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
    evidence.close();
    roomIntegrity.dispose();
    orgCredentials.close();
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
