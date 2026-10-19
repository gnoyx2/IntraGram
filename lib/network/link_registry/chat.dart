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

    // spillToFile: 임계 넘는 긴 메시지는 인라인 대신 .txt 파일 전송으로 보냄
    if (mode == LargeMessageMode.spillToFile &&
        textBytes > kSpillThresholdBytes) {
      await _spillTextToFile(conversationId, text);
      return;
    }
    // inline: 상한 넘는 아웃바운드는 여기서 실패로 기록 (받는
    // 쪽 프레임 가드가 링크를 끊기 전에 막음). unlimited면
    // 통과
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

    // 호스트 중계 방(웹 게스트 또는 앱 그룹): 호스트 메시지를 한 번만 저장하고 나머지 전원에게 뿌림
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
        // 1:1 경로(peer_link_outbound.dart)와 같은 순서: 시도 전에 "전송됨"을 먼저 적지 않음
        delivery: DeliveryState.sending,
      );
      store.addMessage(message);
      await _sendRoomText(message);
      return;
    }

    final link = _links[conversationId];
    if (link == null) {
      // 살아있는 링크가 없음: 시도를 실패로 기록해서 유저가 보게 함
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

  Future<void> _sendRoomText(EphemeralMessage message) async {
    final delivered =
        await _broadcastToRoom(message.conversationId, <String, dynamic>{
          ...InnerFrame.message(
            id: message.id,
            text: message.text!,
            ttlSeconds: message.ttlSeconds,
            timestampMs: message.createdAt.millisecondsSinceEpoch,
            replyToId: message.replyToId,
          ),
          'from': message.senderAlias,
        });
    // 일부 수신자만 읽었어도 나머지에게 못 갔으면 재시도가 필요함
    // sent/delivered는 링크별 실제 소켓 쓰기와 멤버의 ack가 올림
    if (!delivered) store.setDelivery(message.id, DeliveryState.failed);
  }

  // spillToFile 모드의 긴 메시지를 .txt 파일 전송으로 보냄. 보내는
  // 쪽은 디스크에 안 쓰고(source 스트림이 RAM 문자열을 그대로 흘림),
  // 받는 쪽은 평범한 파일 제안으로 보고 수락하면 고른 폴더에 저장
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

  // 막지는 못하고 알리기만 함 (텔레그램 비밀 채팅과 같음). 상대는 시스템 줄로 봄
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

  // 인커밍 메시지를 읽음 처리하고 피어에게 알림 (양쪽 자기파괴 타이머를 lockstep으로 시작)
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

  // 로컬에서 지우고 피어에게 burn을 전달함: store.localBurns 리스너가 앱 링크든 포털 게스트든 알아서 라우팅
  void deleteMessageForEveryone(String messageId) {
    store.userDeletesMessage(messageId);
  }

  // 로컬에서만 지움: store.burnMessage는 _localBurns에 안 실려서 피어에게 신호가 안 가고 상대 화면엔 남음
  void deleteMessageForMe(String messageId) {
    store.burnMessage(messageId);
  }

  // 실패한 버블은 로컬에서 치움 (burnMessage는 _localBurns에 안 실려 피어에게 메아리 안 감)
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
    // 상대(방이면 일부 멤버)가 원본을 받고 확인만 못 보냈을 수 있음: 같은 id로 다시 보내 중복을 막음
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
    store.burnMessage(messageId);
    unawaited(sendText(conversationId, text, replyToId: replyToId));
  }
}
