part of '../link_registry.dart';

// 테스트 전용 seam: 진짜 소켓(RFC1918만 허용) 없이 두 LinkRegistry를
// 인메모리 채널로 잇는 용도. 프로덕션 코드는 절대 안 부름
mixin _LinkRegistryTestSeams on _LinkRegistryState, _LinkRegistrySession {
  @visibleForTesting
  int get debugRoomFileRouteCount => _roomFileRoutes.length;

  @visibleForTesting
  set debugDial(
    Future<StreamChannel<dynamic>> Function(PeerDevice peer) dial,
  ) => _debugDial = dial;

  @visibleForTesting
  set debugNow(DateTime Function() now) => _now = now;

  @visibleForTesting
  int get debugTrackedInboundHosts => _inboundAccepts.length;

  @visibleForTesting
  int get debugInboundReservations => _inboundSlots.length;

  @visibleForTesting
  set debugCreateSession(Future<CryptoSession> Function() create) =>
      _debugCreateSession = create;

  @visibleForTesting
  set debugMaxRoomFileRoutesPerSender(int value) =>
      _maxRoomFileRoutesPerSender = value;

  // connectToPeer와 같은 대화/링크 등록을 하되 소켓 대신 이미 잇대어진
  // channel을 "우리가 다이얼한 링크"로 채택함. 대화 id를 돌려줌
  @visibleForTesting
  Future<String> debugAdoptDialledChannel(
    StreamChannel<dynamic> channel, {
    required String remoteHost,
    required int remotePort,
  }) async {
    final conversationId = newId();
    store.upsertConversation(
      Conversation(
        id: conversationId,
        peerAlias: remoteHost,
        peerPlatform: 'Unknown',
        transport: PeerTransport.app,
        startedAt: DateTime.now(),
        peerHost: remoteHost,
        peerPort: remotePort,
        online: false,
      ),
    );
    await _register(
      conversationId: conversationId,
      channel: channel,
      remoteHost: remoteHost,
      remotePort: remotePort,
      dialledByUs: true,
    );
    return conversationId;
  }
}
