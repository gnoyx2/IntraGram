part of '../in_memory_store.dart';

mixin _StoreMessages on _InMemoryStoreState, _StoreCore {
  void addMessage(EphemeralMessage message) {
    // 대화가 없으면(지운 방에 뒤늦게 온 프레임 등) 받지 않음: 화면에 없는 기록이 RAM·Vault에 남지 않게
    if (_disposed || !_conversations.containsKey(message.conversationId)) {
      return;
    }
    final room = _messages.putIfAbsent(
      message.conversationId,
      () => <String, EphemeralMessage>{},
    );
    if (_messageRooms.containsKey(message.id)) return;
    room[message.id] = message;
    _messageRooms[message.id] = message.conversationId;
    if (message.hasTimer && !message.burned) {
      _armBurnCeiling(message.id, kUnreadBurnCeiling);
    }
    _emitRoom(message.conversationId);
    if (message.direction == MessageDirection.incoming &&
        message.kind != MessageKind.system &&
        !_inboundActivity.isClosed) {
      _inboundActivity.add((
        conversationId: message.conversationId,
        message: message,
      ));
    }
  }

  // 로컬에서만 만들어지고 전선으로 안 나감. 타이머 없고 vault 스냅샷에서도 빠짐
  // 영어 문자열이 아니라 의미(SystemEvent)를 담아서 렌더 시점에 UI가 번역함
  void addSystemMessage(String conversationId, SystemEvent event) {
    addMessage(
      EphemeralMessage(
        id: newId(),
        conversationId: conversationId,
        direction: MessageDirection.incoming,
        kind: MessageKind.system,
        senderAlias: 'system',
        createdAt: DateTime.now(),
        systemEvent: event,
        // 로컬 합성 줄이라 실제 배달 개념이 없어 "sent"는 중립값. 렌더 경로(message_bubble.dart)가
        // system kind는 다른 갈래로 그려서 배달 틱이 안 보임
        delivery: DeliveryState.sent,
      ),
    );
  }

  void _replaceMessage(String conversationId, EphemeralMessage next) {
    final room = _messages[conversationId];
    if (room == null) return;
    if (!room.containsKey(next.id)) return;
    room[next.id] = next;
    _emitRoom(conversationId);
  }

  // 타이머 달린 메시지는 자기파괴 카운트다운도 시작함. 전이된 id들을 리턴해서 호출자가 read 프레임을 보내게 함
  List<String> markIncomingRead(String conversationId) {
    final room = _messages[conversationId];
    if (room == null) return const <String>[];
    final transitioned = <String>[];
    for (final m in List<EphemeralMessage>.of(room.values)) {
      if (m.direction != MessageDirection.incoming) continue;
      if (m.kind == MessageKind.system) continue; // 로컬 알림은 영수증 대상 아님
      if (m.delivery == DeliveryState.read || m.burned) continue;
      _replaceMessage(conversationId, m.copyWith(delivery: DeliveryState.read));
      transitioned.add(m.id);
      if (m.hasTimer) _startBurn(m.id);
    }
    return transitioned;
  }

  // reader는 읽은 사람의 alias. 방에선 멤버별로 누적해 "몇 명 읽음"을 만들고 1:1은 UI가 안 씀
  void applyReadReceipt(String messageId, String reader) {
    final m = _findMessage(messageId);
    if (m == null || m.direction != MessageDirection.outgoing) return;
    if (m.delivery != DeliveryState.read || !m.readBy.contains(reader)) {
      _replaceMessage(
        m.conversationId,
        m.copyWith(
          delivery: m.delivery == DeliveryState.failed
              ? DeliveryState.failed
              : DeliveryState.read,
          readBy: {...m.readBy, reader},
        ),
      );
    }
    // 방이든 1:1이든 소각 카운트다운은 첫 읽음에 시작함 (_startBurn이 멱등이라 이후 읽는 멤버마다 불러도 안전)
    if (m.hasTimer) _startBurn(messageId);
  }

  // 내 메시지 상태는 sending -> sent -> delivered -> read 앞으로만 감 (enum 순서 기준)
  // failed는 재시도 표시라 안 덮고, 이미 읽은 사람이 있으면 read로 맞춤 (재전송 뒤 ack가 read를 내리지 않게)
  void advanceDelivery(String messageId, DeliveryState next) {
    final m = _findMessage(messageId);
    if (m == null || !m.isMine || m.delivery == DeliveryState.failed) return;
    final target = m.readBy.isEmpty ? next : DeliveryState.read;
    if (target.index <= m.delivery.index) return;
    _replaceMessage(m.conversationId, m.copyWith(delivery: target));
  }

  void setDelivery(String messageId, DeliveryState delivery) {
    final m = _findMessage(messageId);
    if (m == null) return;
    _replaceMessage(m.conversationId, m.copyWith(delivery: delivery));
  }

  // senderAlias 하나당 emoji 여러 개 가능 (디스코드식): 이 emoji 하나만 그 사람 집합에 더하거나 뺌
  void applyReaction(
    String messageId,
    String senderAlias,
    String emoji, {
    required bool on,
  }) {
    final m = _findMessage(messageId);
    if (m == null) return;
    final next = Map<String, Set<String>>.of(m.reactions);
    final mine = Set<String>.of(next[senderAlias] ?? const <String>{});
    if (on) {
      mine.add(emoji);
    } else if (!mine.remove(emoji)) {
      return;
    }
    if (mine.isEmpty) {
      next.remove(senderAlias);
    } else {
      next[senderAlias] = mine;
    }
    _replaceMessage(m.conversationId, m.copyWith(reactions: next));
  }

  void _startBurn(String messageId) {
    if (_burnTimers.containsKey(messageId)) return;
    final m = _findMessage(messageId);
    if (m == null || !m.hasTimer || m.burned) return;

    // 읽음 = 실제 카운트다운 시작. 절대 상한 타이머는 여기서 넘겨받음
    _ceilingTimers.remove(messageId)?.cancel();

    final conversationId = m.conversationId;
    _replaceMessage(
      m.conversationId,
      m.copyWith(burnAt: DateTime.now().add(Duration(seconds: m.ttlSeconds))),
    );
    _burnTimers[messageId] = Timer(Duration(seconds: m.ttlSeconds), () {
      if (!_localBurns.isClosed) {
        _localBurns.add((conversationId: conversationId, messageId: messageId));
      }
      burnMessage(messageId);
    });
  }

  void oweReads(String conversationId, Iterable<String> messageIds) {
    if (!_conversations.containsKey(conversationId)) return;
    _owedReads.putIfAbsent(conversationId, () => <String>{}).addAll(messageIds);
  }

  void oweBurn(String conversationId, String messageId) {
    if (!_conversations.containsKey(conversationId)) return;
    _owedBurns.putIfAbsent(conversationId, () => <String>{}).add(messageId);
  }

  // 한 번 꺼내면 비움. 소각을 보낼 메시지는 읽음을 따로 안 보냄
  ({List<String> reads, List<String> burns}) takeOwed(String conversationId) {
    final burns = _owedBurns.remove(conversationId) ?? const <String>{};
    final reads = _owedReads.remove(conversationId) ?? const <String>{};
    return (reads: reads.difference(burns).toList(), burns: burns.toList());
  }

  // 로컬에서 지우고 피어에도 burn을 보내도록 localBurns에 실음 (타이머 만료와 같은 경로)
  // 인바운드 burn 처리는 burnMessage만 불러서 메아리가 없음
  void userDeletesMessage(String messageId) {
    final m = _findMessage(messageId);
    if (m == null) return;
    if (!_localBurns.isClosed) {
      _localBurns.add((conversationId: m.conversationId, messageId: messageId));
    }
    burnMessage(messageId);
  }
}
