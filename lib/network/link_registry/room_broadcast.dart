part of '../link_registry.dart';

extension _RoomBroadcast on _LinkRegistryState {
  // 현재 방 링크 전부에 쓰기가 성공해야 true (받는 사람이 없으면
  // 실패). 필수 프레임을 못 받은 링크는 닫아 명단/전송 상태가 수렴하게
  // 함
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
      // 종료 콜백/채널도 던질 수 있음: 필수 프레임은 링크를 닫고 실패로 반환
      if (requiredDelivery) {
        try {
          await link.close();
        } on Object {
          // 이미 닫히는 중인 링크의 cleanup 실패: 전달은 실패로 남김
        }
      }
      return false;
    }
  }
}
