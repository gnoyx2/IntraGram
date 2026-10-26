part of '../in_memory_store.dart';

mixin _StoreMutations on _InMemoryStoreState, _StoreCore {
  void upsertConversation(Conversation conversation) {
    if (_disposed) return;
    _conversations[conversation.id] = conversation;
    _messages.putIfAbsent(conversation.id, () => <String, EphemeralMessage>{});
    _emitConversations();
  }

  void updateConversation(
    String id,
    Conversation Function(Conversation current) update,
  ) {
    final current = _conversations[id];
    if (current == null) return;
    final next = update(current);
    if (next == current) return;
    _conversations[id] = next;
    // 온라인·타이핑·세션 검증 등 RAM 전용 변경은 저장을 깨우지 않음
    _emitConversations(
      persist:
          !const MapEquality<String, dynamic>().equals(
            current.toJson(),
            next.toJson(),
          ) ||
          current.vaultOptOut != next.vaultOptOut ||
          current.isRoom != next.isRoom,
    );
  }

  void setConversationOnline(String id, {required bool online}) =>
      updateConversation(id, (c) => c.copyWith(online: online));

  void setPeerTyping(String id, {required bool typing}) {
    _typingTimers.remove(id)?.cancel();
    if (typing) {
      _typingTimers[id] = Timer(
        kTypingIdleTimeout,
        () => _setPeerTypingRaw(id, typing: false),
      );
    }
    _setPeerTypingRaw(id, typing: typing);
  }

  void _setPeerTypingRaw(String id, {required bool typing}) =>
      updateConversation(id, (c) => c.copyWith(peerTyping: typing));

  void setOutgoingTtl(String id, int seconds) =>
      updateConversation(id, (c) => c.copyWith(outgoingTtlSeconds: seconds));

  void setConversationSas(String id, String sas) =>
      updateConversation(id, (c) => c.copyWith(sas: sas));

  void setLocalVerified(String id) =>
      updateConversation(id, (c) => c.copyWith(localVerified: true));

  void setPeerVerified(String id) =>
      updateConversation(id, (c) => c.copyWith(peerVerified: true));

  void clearVerified(String id) => updateConversation(
    id,
    (c) => c.copyWith(localVerified: false, peerVerified: false),
  );

  void setConversationAutoAccept(String id, {required bool value}) =>
      updateConversation(id, (c) => c.copyWith(autoAcceptFiles: value));

  // 새 세션이라 확인 상태는 늘 false로 초기화함 (키가 바뀌었는데 '확인됨'이 남으면 중간자 방어가 무력화됨). sas는 setRoomMemberSas가 다시 채움
  void upsertRoomMember(
    String id,
    String peerId, {
    required String alias,
    required String platform,
  }) => updateConversation(id, (c) {
    final members = Map<String, RoomMember>.of(c.members);
    members[peerId] = RoomMember(alias: alias, platform: platform);
    return c.copyWith(members: members);
  });

  void setRoomMemberSas(String id, String peerId, String sas) =>
      updateConversation(id, (c) {
        final existing = c.members[peerId];
        if (existing == null) return c;
        final members = Map<String, RoomMember>.of(c.members);
        members[peerId] = existing.copyWith(sas: sas);
        return c.copyWith(members: members);
      });

  void setRoomMemberLocalVerified(String id, String peerId) =>
      updateConversation(id, (c) {
        final existing = c.members[peerId];
        if (existing == null) return c;
        final members = Map<String, RoomMember>.of(c.members);
        members[peerId] = existing.copyWith(localVerified: true);
        return c.copyWith(members: members);
      });

  // 이름만 바꿈 (본인이 보냈거나 호스트가 중계한 것). upsertRoomMember와 달리 SAS/검증 상태는 안 건드림
  void renameRoomMember(String id, String peerId, String alias) =>
      updateConversation(id, (c) {
        final existing = c.members[peerId];
        if (existing == null) return c;
        final members = Map<String, RoomMember>.of(c.members);
        members[peerId] = existing.copyWith(alias: alias);
        return c.copyWith(members: members);
      });

  void setRoomMemberOffline(String id, String peerId) =>
      updateConversation(id, (c) {
        final existing = c.members[peerId];
        if (existing == null) return c;
        final members = Map<String, RoomMember>.of(c.members);
        members[peerId] = existing.goOffline();
        return c.copyWith(members: members);
      });

  void setRoomMemberPeerVerified(String id, String peerId) =>
      updateConversation(id, (c) {
        final existing = c.members[peerId];
        if (existing == null) return c;
        final members = Map<String, RoomMember>.of(c.members);
        members[peerId] = existing.copyWith(peerVerified: true);
        return c.copyWith(members: members);
      });

  // 나가면서 '저장 안 함'을 고른 대화: 다음 저장부터 파일에서 통째로 빠짐
  void setVaultOptOut(String id, {required bool value}) =>
      updateConversation(id, (c) => c.copyWith(vaultOptOut: value));

  void bumpUnread(String id) =>
      updateConversation(id, (c) => c.copyWith(unread: c.unread + 1));

  void clearUnread(String id) =>
      updateConversation(id, (c) => c.copyWith(unread: 0));

  void upsertTransfer(FileTransfer transfer) {
    if (_disposed) return;
    _transfers[transfer.id] = transfer;
    _emitTransfers();
  }

  void updateTransfer(
    String id,
    FileTransfer Function(FileTransfer current) update,
  ) {
    final current = _transfers[id];
    if (current == null) return;
    final next = update(current);
    if (next == current && next.bytesPerSecond == current.bytesPerSecond) {
      return;
    }
    _transfers[id] = next;
    // 완료 전 전송은 스냅샷에 없으므로 진행률은 UI에만 알림
    _emitTransfers(persist: current.isDone || next.isDone);
  }
}
