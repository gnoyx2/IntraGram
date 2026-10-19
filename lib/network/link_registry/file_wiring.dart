part of '../link_registry.dart';

// 링크가 올리는 파일 제어 프레임 콜백(accept/reject/cancel/received/retry)을
// TransferCoordinator 처리기에 잇는 배선
mixin _LinkRegistryFileWiring on _LinkRegistryState {
  void _wireFileCallbacks(PeerLink link) {
    // 호스트: 방 파일 제어 프레임의 경로 검사. 멤버: 호스트가 알린 방 앱 피어 목록이 바뀌면 방을 나간 수신자를 실패로 돌림
    link.authorizeRoomFileControl = _canRouteRoomFileControl;
    link.onRoomRoster = (peerIds) =>
        _transfers.outgoing.handleRoomRoster(link.conversationId, peerIds);
    // 프레임 발신자(인가 단계가 도장 찍은 peerId)를 수신자 키로 바꿈: 이 링크 상대 자신이면 링크의 수신자 키,
    // 호스트가 중계한 다른 멤버면 그 멤버의 peerId 그대로 (그 수신자가 맞는지는 outgoing이 검사)
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
    // 호스트가 그 수신자에게 offer를 못 넘김: 수신자 키는 그 멤버의 peerId 그대로
    link.onFileUnavailable = (transferId, attemptId, targetId) {
      _transfers.outgoing.handleUnavailable(
        transferId,
        attemptId: attemptId,
        targetKey: targetId,
      );
    };
  }
}
