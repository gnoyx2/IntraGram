part of '../in_memory_store.dart';

mixin _StorePersistence on _InMemoryStoreState, _StoreCore {
  // 절대 안 담음: 소각된 메시지, 시스템 줄, 안 끝난 전송 (재시작하면 의미 없음). 대화는 담을 항목이 있을 때만 포함함
  VaultSnapshot toSnapshot(VaultSettings settings) {
    // 방이거나 사용자가 "저장 안 함"을 고른 대화, 대화가 없는 기록(지운 대화의 잔여)은 통째로 뺌
    bool skip(String conversationId) {
      final c = _conversations[conversationId];
      return c == null || c.isRoom || c.vaultOptOut;
    }

    final messages = <EphemeralMessage>[];
    if (settings.keepMessages) {
      for (final entry in _messages.entries) {
        if (skip(entry.key)) continue;
        for (final m in entry.value.values) {
          if (m.burned || m.kind == MessageKind.system) continue;
          messages.add(m);
        }
      }
    }
    final transfers = <FileTransfer>[];
    if (settings.keepTransfers) {
      for (final t in _transfers.values) {
        if (t.voice) continue; // 음성은 RAM 전용이라 절대 보관 안 함
        if (t.state == TransferState.complete && !skip(t.conversationId)) {
          transfers.add(t);
        }
      }
    }
    final keptIds = <String>{
      ...messages.map((m) => m.conversationId),
      ...transfers.map((t) => t.conversationId),
    };
    return VaultSnapshot(
      settings: settings,
      conversations: <Conversation>[
        for (final c in _conversations.values)
          if (!c.isRoom && !c.vaultOptOut && keptIds.contains(c.id)) c,
      ],
      messages: messages,
      transfers: transfers,
    );
  }

  // 앱 시작 시 한 번 호출함. 되살린 대화는 오프라인 아카이브이고 라이브 링크는 나중에 새 대화로 붙음
  // 소각 시각이 지난 메시지는 되살리지 않고, 안 끝난 카운트다운은 남은 시간으로 다시 걺
  void hydrate(VaultSnapshot snap, {DateTime? now}) {
    if (_disposed) return;
    final clock = now ?? DateTime.now();

    for (final c in snap.conversations) {
      _conversations[c.id] = c;
      _messages.putIfAbsent(c.id, () => <String, EphemeralMessage>{});
    }
    for (final m in snap.messages) {
      // 대화 없는 메시지(예전 버전이 남긴 지운 방의 잔여)는 되살리지 않음
      if (!_conversations.containsKey(m.conversationId)) continue;
      if (m.burnAt != null && m.burnAt!.isBefore(clock)) continue;

      // 안 읽힌 채 절대 상한이 이미 지난 타이머 메시지는 되살리지 않음
      final ceilingLeft = m.hasTimer && m.burnAt == null
          ? kUnreadBurnCeiling - clock.difference(m.createdAt)
          : null;
      if (ceilingLeft != null && ceilingLeft <= Duration.zero) continue;

      final room = _messages.putIfAbsent(
        m.conversationId,
        () => <String, EphemeralMessage>{},
      );
      if (_messageRooms.containsKey(m.id)) continue;
      room[m.id] = m;
      _messageRooms[m.id] = m.conversationId;
      if (m.hasTimer && m.burnAt != null && m.burnAt!.isAfter(clock)) {
        _rearmBurn(m.id, m.burnAt!.difference(clock));
      } else if (ceilingLeft != null) {
        _armBurnCeiling(m.id, ceilingLeft);
      }
    }
    for (final t in snap.transfers) {
      if (_conversations.containsKey(t.conversationId)) _transfers[t.id] = t;
    }

    _emitConversations();
    _emitTransfers();
    for (final id in _messages.keys) {
      _emitRoom(id);
    }
  }

  void _rearmBurn(String messageId, Duration remaining) {
    if (_burnTimers.containsKey(messageId)) return;
    _burnTimers[messageId] = Timer(remaining, () {
      final m = _findMessage(messageId);
      if (m != null && !_localBurns.isClosed) {
        _localBurns.add((
          conversationId: m.conversationId,
          messageId: messageId,
        ));
      }
      burnMessage(messageId, cause: BurnCause.ttlAfterRead);
    });
  }

  void stopPersisting() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _saveMaxWait?.cancel();
    _saveMaxWait = null;
    onPersistableChange = null;
  }
}
