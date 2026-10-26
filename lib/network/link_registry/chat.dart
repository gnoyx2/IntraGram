part of '../link_registry.dart';

mixin _LinkRegistryChat on _LinkRegistryState {
  Future<void> sendText(
    String conversationId,
    String text, {
    String? replyToId,
  }) async {
    final conversation = store.conversation(conversationId);
    if (conversation == null || text.isEmpty) return;

    final mode = store.largeMessageMode;
    final textBytes = utf8.encode(text).length;

    if (mode == LargeMessageMode.spillToFile &&
        textBytes > kSpillThresholdBytes) {
      await _spillTextToFile(conversationId, text);
      return;
    }
    // inline 상한을 넘으면 여기서 실패로 남김 (받는 쪽 프레임 가드가 링크를 끊기 전에)
    if (mode == LargeMessageMode.inline && textBytes > kMaxInlineMessageBytes) {
      store.addMessage(
        EphemeralMessage(
          id: newId(),
          conversationId: conversationId,
          direction: MessageDirection.outgoing,
          kind: MessageKind.text,
          senderAlias: identity.alias,
          createdAt: DateTime.now(),
          text: text,
          replyToId: replyToId,
          delivery: DeliveryState.failed,
        ),
      );
      return;
    }

    // 내가 호스트인 방: 한 번 저장하고 전원에게 뿌림
    if (_isRoomHub(conversationId)) {
      final id = newId();
      final now = DateTime.now();
      final ttl = conversation.outgoingTtlSeconds;
      final message = EphemeralMessage(
        id: id,
        conversationId: conversationId,
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: identity.alias,
        createdAt: now,
        text: text,
        replyToId: replyToId,
        ttlSeconds: ttl,
        // 1:1과 같음: 써 보기 전에 '전송됨'을 안 적음
        delivery: DeliveryState.sending,
      );
      store.addMessage(message);
      await _sendRoomText(message);
      return;
    }

    final link = _links[conversationId];
    if (link == null) {
      store.addMessage(
        EphemeralMessage(
          id: newId(),
          conversationId: conversationId,
          direction: MessageDirection.outgoing,
          kind: MessageKind.text,
          senderAlias: identity.alias,
          createdAt: DateTime.now(),
          text: text,
          replyToId: replyToId,
          delivery: DeliveryState.failed,
        ),
      );
      return;
    }
    await link.sendText(
      text,
      ttlSeconds: conversation.outgoingTtlSeconds,
      replyToId: replyToId,
    );
  }

  // 긴 메시지를 .txt 전송으로 보냄. 보내는 쪽은 디스크에 안 쓰고 RAM 문자열을 그대로 흘림
  Future<void> _spillTextToFile(String conversationId, String text) {
    return _transfers.outgoing.offerInlineText(
      conversationId,
      'message.txt',
      text,
    );
  }

  void toggleReaction(String conversationId, String messageId, String emoji) {
    final mine = store.messageById(messageId)?.reactions[identity.peerId];
    final on = !(mine?.contains(emoji) ?? false);
    store.applyReaction(messageId, identity.peerId, emoji, on: on);
    if (_isRoomHub(conversationId)) {
      unawaited(
        _broadcastToRoom(conversationId, <String, dynamic>{
          ...InnerFrame.react(id: messageId, emoji: emoji, on: on),
          'from': identity.alias,
        }),
      );
    } else {
      final link = _links[conversationId];
      if (link != null) {
        unawaited(
          link.sendRawInnerOrClose(
            InnerFrame.react(id: messageId, emoji: emoji, on: on),
          ),
        );
      }
    }
  }

  Future<void> sendTyping(String conversationId, {required bool active}) async {
    if (_isRoomHub(conversationId)) {
      await _broadcastToRoom(conversationId, <String, dynamic>{
        ...InnerFrame.typing(active: active),
        'from': identity.alias,
      }, requiredDelivery: false);
      return;
    }
    await _links[conversationId]?.deliverRawInner(
      InnerFrame.typing(active: active),
    );
  }

  // 막지는 못하고 알리기만 함 (텔레그램 비밀 채팅처럼)
  void notifyScreenshot(String conversationId) {
    if (_isRoomHub(conversationId)) {
      unawaited(
        _broadcastToRoom(conversationId, <String, dynamic>{
          ...InnerFrame.screenshot(),
          'from': identity.alias,
        }),
      );
      return;
    }
    final link = _links[conversationId];
    if (link != null) {
      unawaited(link.sendRawInnerOrClose(InnerFrame.screenshot()));
    }
  }

  // 읽음 처리하고 알림: 양쪽 소각 타이머가 같이 시작함
  Future<void> markRoomRead(String conversationId) async {
    final ids = store.markIncomingRead(conversationId);
    store.clearUnread(conversationId);
    if (ids.isEmpty) return;
    if (_isRoomHub(conversationId)) {
      for (final id in ids) {
        await _broadcastToRoom(conversationId, InnerFrame.read(id));
      }
      return;
    }
    // 못 보낸 영수증은 다음 링크가 갚음: 안 그러면 보낸 쪽 카운트다운이 안 돌아 사본이 24시간 상한까지 남음
    final link = _links[conversationId];
    if (link == null) {
      store.oweReads(conversationId, ids);
      return;
    }
    for (var i = 0; i < ids.length; i++) {
      if (!await link.sendRawInnerOrClose(InnerFrame.read(ids[i]))) {
        store.oweReads(conversationId, ids.skip(i));
        return;
      }
    }
  }

  void setBurnTimer(String conversationId, int seconds) {
    store.setOutgoingTtl(conversationId, seconds);
  }

  // burn은 store.localBurns 리스너가 1:1이든 방이든 알아서 보냄
  void deleteMessageForEveryone(String messageId) {
    store.userDeletesMessage(messageId);
  }

  // 내 쪽만 지움: burnMessage는 localBurns에 안 실려서 상대 화면엔 남음
  void deleteMessageForMe(String messageId) {
    store.burnMessage(messageId, cause: BurnCause.deletedForMe);
  }

  // 같은 id로 다시 못 보내면(크기 모드가 바뀜, 링크 없음) 실패 버블은 내 쪽에서만 치우고 새로 보냄
  void resendFailed(String messageId) {
    final message = store.messageById(messageId);
    if (message == null ||
        message.delivery != DeliveryState.failed ||
        message.kind != MessageKind.text ||
        message.text == null) {
      return;
    }
    final conversationId = message.conversationId;
    final text = message.text!;
    final replyToId = message.replyToId;
    final bytes = utf8.encode(text).length;
    final fits =
        !(store.largeMessageMode == LargeMessageMode.spillToFile &&
            bytes > kSpillThresholdBytes) &&
        !(store.largeMessageMode == LargeMessageMode.inline &&
            bytes > kMaxInlineMessageBytes);
    // 상대(방이면 일부 멤버)가 받고 확인만 못 보냈을 수 있음: 같은 id로 다시 보내서 중복을 막음
    final link = _links[conversationId];
    if (fits && _isRoomHub(conversationId)) {
      store.setDelivery(messageId, DeliveryState.sending);
      unawaited(_sendRoomText(message));
      return;
    }
    if (fits && link != null) {
      store.setDelivery(messageId, DeliveryState.sending);
      unawaited(link.resendText(message));
      return;
    }
    store.burnMessage(messageId, cause: BurnCause.replaced);
    unawaited(sendText(conversationId, text, replyToId: replyToId));
  }
}
