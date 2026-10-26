part of '../link_registry.dart';

extension _RoomBroadcast on _LinkRegistryState {
  // 방 링크 전부에 써져야 true (받을 사람이 없어도 false). 필수 프레임을 못 받은 링크는 닫아서 명단·전송 상태가 맞춰지게 함
  Future<bool> _broadcastToRoom(
    String roomId,
    Map<String, dynamic> inner, {
    PeerLink? except,
    bool requiredDelivery = true,
  }) async {
    final sends = <Future<bool>>[];
    for (final link in _roomLinks.toList()) {
      if (link.conversationId != roomId || link.isClosed) continue;
      if (identical(link, except)) continue;
      sends.add(_sendToRoomLink(link, inner, requiredDelivery));
    }
    if (sends.isEmpty) return false;
    final delivered = await Future.wait(sends);
    return delivered.every((ok) => ok);
  }

  Future<bool> _sendToRoomLink(
    PeerLink link,
    Map<String, dynamic> inner,
    bool requiredDelivery,
  ) async {
    try {
      return await (requiredDelivery
          ? link.sendRawInnerOrClose(inner)
          : link.deliverRawInner(inner));
    } on Object {
      // 종료 콜백·채널도 던질 수 있음
      if (requiredDelivery) {
        try {
          await link.close();
        } on Object {
          // 이미 닫히는 중: 전달 실패로 남김
        }
      }
      return false;
    }
  }

  Future<void> _sendRoomText(EphemeralMessage message) async {
    // 작성자 서명·체크포인트는 앱 방만 적용함 (브라우저 게스트 방은 평문이라 기존 프레임을 그대로 씀)
    final appRoom = message.conversationId == _appRoomId;
    if (appRoom) _ensureRoomIntegrity(message.conversationId);
    final wire = await store.roomIntegrity
        .sign(message.conversationId, identity, <String, dynamic>{
          ...InnerFrame.message(
            id: message.id,
            text: message.text!,
            ttlSeconds: message.ttlSeconds,
            timestampMs: message.createdAt.millisecondsSinceEpoch,
            replyToId: message.replyToId,
          ),
          'from': message.senderAlias,
        });
    if (wire == null ||
        _disposed ||
        store.messageById(message.id)?.conversationId !=
            message.conversationId) {
      return;
    }
    final delivered = await _broadcastToRoom(message.conversationId, wire);
    if (appRoom && store.conversation(message.conversationId) != null) {
      _broadcastRoomState(message.conversationId);
    }
    // 한 명이라도 못 받았으면 실패 (다시 보낼 수 있게). sent·delivered는 링크별 소켓 쓰기와 ack가 올림
    if (!delivered) store.setDelivery(message.id, DeliveryState.failed);
  }
}
