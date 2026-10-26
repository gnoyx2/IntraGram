part of '../link_registry.dart';

// 링크의 파일 제어 콜백을 TransferCoordinator 처리기에 잇는 배선
mixin _LinkRegistryFileWiring on _LinkRegistryState {
  void _wireFileCallbacks(PeerLink link) {
    // 호스트: 방 파일 제어 프레임의 경로 검사. 멤버: 호스트가 알린 방 앱 피어 목록이 바뀌면 방을 나간 수신자를 실패로 돌림
    link.authorizeRoomFileControl = _canRouteRoomFileControl;
    link.onRoomRoster = (peerIds) =>
        _transfers.outgoing.handleRoomRoster(link.conversationId, peerIds);
    // 발신자를 수신자 키로: 링크 상대 자신이면 링크의 키, 호스트가 중계한 멤버면 그 peerId (맞는지는 outgoing이 봄)
    String actorKey(String actor) =>
        (actor == link.remotePeerId || actor == link.peerAlias)
        ? recipientKeyOf(link)
        : actor;
    link.onFileAccepted = (transferId, attemptId, pushToken, actor) {
      _transfers.outgoing.handleAccepted(
        transferId,
        attemptId: attemptId,
        pushToken: pushToken,
        actorKey: actorKey(actor),
      );
    };
    link.onFileRejected = (transferId, attemptId, actor) {
      _transfers.outgoing.handleRejected(
        transferId,
        attemptId: attemptId,
        actorKey: actorKey(actor),
      );
    };
    link.onFileCancelled = (transferId, attemptId, actor) {
      // 방향을 몰라서 둘 다 부르고 각자 자기 것 아니면 조용히 무시
      _transfers.outgoing.handleCancelledByPeer(
        transferId,
        attemptId: attemptId,
        actorKey: actorKey(actor),
      );
      _transfers.incoming.handleCancelledByPeer(
        transferId,
        attemptId: attemptId,
        senderPeerId: actor,
      );
    };
    link.onDeliveryReceipt = (transferId, attemptId, actor, receipt) {
      _transfers.outgoing.handleDeliveryReceipt(
        transferId,
        attemptId: attemptId,
        actorKey: actorKey(actor),
        receipt: receipt,
      );
    };
    link.onFileReceived = (transferId, attemptId, actor) {
      _transfers.outgoing.handleFileReceived(
        transferId,
        attemptId: attemptId,
        actorKey: actorKey(actor),
      );
    };
    link.onFileRetryRequested = (transferId, attemptId, actor) {
      unawaited(
        _transfers.outgoing.handleRetryRequested(
          transferId,
          attemptId: attemptId,
          actorKey: actorKey(actor),
        ),
      );
    };
    // 호스트가 그 수신자에게 offer를 못 넘김 (키는 그 멤버 peerId 그대로)
    link.onFileUnavailable = (transferId, attemptId, targetId) {
      _transfers.outgoing.handleUnavailable(
        transferId,
        attemptId: attemptId,
        targetKey: targetId,
      );
    };
  }
}
