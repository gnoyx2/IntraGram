part of 'outgoing_transfers.dart';

// 방 멤버로서 내는 offer: 멤버끼리 직접 링크가 없어서 호스트 링크로만 나가고 to로 수신자를 지정함.
// 수신자(호스트 포함)마다 attempt·토큰·상태가 따로라 한 명의 실패·재시도가 다른 수신자에게 안 번짐
extension OutgoingTransfersRelay on OutgoingTransfers {
  // 다음 홉은 확정된 호스트 peerId로 증명된 열린 링크뿐 (그 외 링크로는 offer도 취소도 안 보냄)
  PeerLink? _relayHostLink(String conversationId) {
    final hostId = store.conversation(conversationId)?.hostPeerId;
    final link = _linkFor(conversationId);
    if (hostId == null || link == null || link.isClosed) return null;
    return link.remotePeerId == hostId ? link : null;
  }

  // 명단에서 본인을 제외한 전원(호스트 포함)을 수신자로 등록해 순차적으로 offer를 발송함. 호스트 링크나 멤버 명단이 올바르지 않으면 실패 처리함
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

  // 멤버 명단 갱신: 제외된(퇴장·연결 종료) 수신자는 실패로 전환함 (재입장 시 재시도 가능함). 빈 목록은 정보 부재로 간주해 무시함
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
