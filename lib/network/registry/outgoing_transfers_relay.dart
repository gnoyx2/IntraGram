part of 'outgoing_transfers.dart';

// 방의 일반 멤버가 내는 offer의 수신자별 라우팅: 방 멤버끼리는 직접 링크가 없어서 offer는 인증된 호스트 링크 하나로만 나가고
// to로 수신자를 지정함 (호스트가 그 멤버에게만 중계). 수신자(호스트 자신
// 포함, 방의 앱 멤버 전원)마다 자기 attempt/일회용 pull 토큰/상태를
// 따로 가져서 한 수신자의 토큰/ACK/실패/재시도가 다른 수신자에게 번지지 않음
extension OutgoingTransfersRelay on OutgoingTransfers {
  // 방 멤버로서 내는 offer의 유일한 다음 홉: 대화가 확정한 호스트
  // peerId와 링크의 인증된 peerId가 정확히 같은 열린 링크만
  // 인정
  // (그 외 링크로는 offer도 취소도 안 보냄)
  PeerLink? _relayHostLink(String conversationId) {
    final hostId = store.conversation(conversationId)?.hostPeerId;
    final link = _linkFor(conversationId);
    if (hostId == null || link == null || link.isClosed) return null;
    return link.remotePeerId == hostId ? link : null;
  }

  // 호스트가 알린 방 명단의 나 말고 모든 앱 멤버(호스트 포함)를 수신자로 등록하고 호스트 링크로 하나씩 offer
  // 호스트 링크나 명단(호스트와 나 포함)을 확인 못 하면 정직하게 failed, 링크에 못 실은 수신자는 그 자리에서 실패로 기록
  Future<void> _offerViaRelayHost(
    String transferId,
    OutgoingFileSource source, {
    required ({String host, int port})? endpoint,
    String? firstAttemptId,
  }) async {
    final host = _relayHostLink(source.conversationId);
    final peers =
        store.conversation(source.conversationId)?.roomRecipientIds ??
        const <String>[];
    if (host == null ||
        !peers.contains(host.remotePeerId) ||
        !peers.contains(identity.peerId)) {
      _failOffer(this, transferId);
      return;
    }
    var first = true;
    var undelivered = false;
    for (final target in peers.where((id) => id != identity.peerId)) {
      final recipient = _OutgoingRecipient(
        key: target,
        attemptId: first ? (firstAttemptId ?? newId()) : newId(),
        pullToken: generateSecureToken(),
      );
      first = false;
      source._recipients[target] = recipient;
      final sent = await _sendOffer(
        source,
        host,
        transferId,
        recipient,
        endpoint: endpoint,
      );
      if (!sent) {
        recipient.fail();
        undelivered = true;
      }
    }
    if (undelivered) _syncTransfer(transferId);
  }

  // 호스트가 알린 방 앱 피어 목록 갱신(room_join/room_state):
  // 목록에서 사라진(방을 나갔거나 끊긴) 수신자는 실패로 돌림
  // (호스트가 그 멤버에게 offer를 못 넘기고, 돌아오면 재시도할 수 있음).
  // 나머지 수신자의 진행/완료 상태는 그대로 빈 목록은 명단 정보가 없는 것이라 무시
  void handleRoomRoster(String conversationId, List<String> peerIds) {
    if (peerIds.isEmpty) return;
    for (final entry in _outgoing.entries.toList()) {
      final source = entry.value;
      if (!source.viaRelayHost || source.conversationId != conversationId) {
        continue;
      }
      var changed = false;
      for (final recipient in source._recipients.values) {
        if (recipient.isTerminal ||
            recipient.phase == _RecipientPhase.failed ||
            peerIds.contains(recipient.key)) {
          continue;
        }
        recipient.fail();
        changed = true;
      }
      if (changed) _syncTransfer(entry.key);
    }
  }
}
