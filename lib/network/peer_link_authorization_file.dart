part of 'peer_link.dart';

// 파일 프레임 인가: 거부할 프레임이 중계로 새면 안 돼서 충돌·다운그레이드·mode 검사가 전부 이 입구에 있음
extension _PeerLinkAuthorizationFile on PeerLink {
  // 수락 가능한 offer인지 검사함: 방(공유 키 없음)은 항상 평문, 1:1은 항상 암호화되어야 함 (어긋나면 다운그레이드로 보고 거부함). pull은 방이나 1:1 음성에서만 허용하며,
  // 같은 id 전송이 이미 있으면 동일 발신자의 멱등 재전송일 때만 허용함
  bool _authorizeFileOffer(FileOfferInner offer) {
    final conversation = store.conversation(conversationId);
    if (conversation == null) return false;
    final isRoom = conversation.isRoom;
    if (isRoom == offer.enc) return false;
    if (offer.mode == 'pull' && !isRoom && !offer.voice) return false;
    if (offer.to != null) {
      if (!isRoom || _phase != _LinkPhase.app) return false;
      if (_roomRole == _RoomLinkRole.localHostMember) {
        if (offer.to == remotePeerId || offer.srcHost != remoteHost) {
          return false;
        }
      } else if (_roomRole != _RoomLinkRole.remoteHost ||
          offer.to != identity.peerId) {
        return false;
      }
    } else if (_roomRole == _RoomLinkRole.localHostMember) {
      return false;
    }
    // 웹 게스트가 명시한 원본 주소도 자신의 링크 주소와 일치해야 함 (호스트가 게스트가 지정한 임의의 사설 주소로 요청을 보내지 못하게 막음)
    if (_roomRole == _RoomLinkRole.webGuest &&
        offer.srcHost != null &&
        offer.srcHost != remoteHost) {
      return false;
    }
    final senderKey = offer.senderPubKey;
    final keyBytes = wireBytes(senderKey, length: 32);
    if (senderKey != null &&
        (keyBytes == null ||
            isSmallOrderKey(keyBytes) ||
            peerIdOfKey(keyBytes) != _resolveActor(offer.peerId))) {
      return false;
    }
    final existing = store.transfer(offer.id);
    if (existing == null) return true;
    return _isReofferOfSameTransfer(
      existing,
      offer,
      routed:
          _roomRole == _RoomLinkRole.localHostMember &&
          offer.to != identity.peerId,
    );
  }

  // 유효한 재offer인지 확인함: attempt가 같으면 멱등 재전송이고, 다르면 수락 전(offered)이나 실패한(failed) 전송을 새 attempt로
  // 다시 협상할 때만 허용함 (진행 중이거나 완료된 전송은 교체할 수 없음)
  bool _isReofferOfSameTransfer(
    FileTransfer existing,
    FileOfferInner offer, {
    bool routed = false,
  }) {
    if (existing.conversationId != conversationId) return false;
    if (existing.direction != TransferDirection.incoming) return false;
    if (existing.senderPeerId != _resolveActor(offer.peerId)) return false;
    final mode = offer.mode == 'pull'
        ? FileTransferMode.pull
        : FileTransferMode.push;
    if (existing.fileName != safeBasename(offer.name) ||
        existing.totalBytes != offer.size ||
        existing.voice != offer.voice ||
        existing.encrypted != offer.enc ||
        existing.digest != offer.digest ||
        existing.mode != mode) {
      return false;
    }
    // 호스트의 수신 상태로 다른 멤버의 독립 시도를 막으면 안 됨: 같은 발신자의 같은 파일인지만 보고 시도는 라우터 몫
    if (routed || existing.attemptId == offer.attempt) return true;
    return existing.state == TransferState.offered ||
        existing.state == TransferState.failed;
  }

  // accept/reject/cancel/received/retry는 이 대화 전송만 가리켜야 함 (모르는 id면 거부라 탐색도 못 함). 반환값은 중계 여부.
  // 지금 attempt·수신자 검사는 registry가 하고 거부된 프레임은 상태를 안 건드림
  bool? _authorizeFileControl(
    String kind,
    String id,
    String attempt,
    String actor,
  ) {
    final transfer = store.transfer(id);
    if (transfer == null || transfer.conversationId != conversationId) {
      return null;
    }
    // 인커밍은 이 store가 지금 attempt를 알아서 낡은 제어 프레임은 로컬 처리도 중계도 안 함
    if (transfer.direction == TransferDirection.incoming) {
      if ((transfer.attemptId ?? transfer.id) != attempt ||
          transfer.senderPeerId != actor ||
          kind != 'file_cancel') {
        return null;
      }
      return false;
    }
    return false;
  }

  // 호스트가 보낸 file_unavailable 프레임 검사: 링크 상대가 이 방의 확정된 호스트이고 내 발신 전송을 가리킬 때만 통과시킴. 위조 프레임은 거부하고 중계하지 않음
  bool _authorizeFileUnavailable(String id) {
    if (_phase != _LinkPhase.app || _roomRole != _RoomLinkRole.remoteHost) {
      return false;
    }
    final conversation = store.conversation(conversationId);
    final hostPeerId = conversation?.hostPeerId;
    if (conversation == null ||
        !conversation.isRoom ||
        hostPeerId == null ||
        hostPeerId != remotePeerId) {
      return false;
    }
    final transfer = store.transfer(id);
    return transfer != null &&
        transfer.conversationId == conversationId &&
        transfer.direction == TransferDirection.outgoing;
  }

  // 호스트로서 멤버에게서 수신한 파일 제어 프레임이 등록된 (전송, attempt) 경로의 인증된 대상(cancel은 발신자 포함)에게서 왔는지 확인함.
  // 유효하면 반대편 멤버 몫이므로 로컬 처리 없이 중계만 수행함
  bool _routedRoomFileControl(InboundInner inner) {
    if (_roomRole != _RoomLinkRole.localHostMember) return false;
    final check = authorizeRoomFileControl;
    if (check == null) return false;
    return switch (inner) {
      FileAcceptInner(:final id, :final attempt) => check(
        this,
        'file_accept',
        id,
        attempt,
      ),
      FileRejectInner(:final id, :final attempt) => check(
        this,
        'file_reject',
        id,
        attempt,
      ),
      FileCancelInner(:final id, :final attempt) => check(
        this,
        'file_cancel',
        id,
        attempt,
      ),
      FileReceivedInner(:final id, :final attempt) => check(
        this,
        'file_received',
        id,
        attempt,
      ),
      FileRetryInner(:final id, :final attempt) => check(
        this,
        'file_retry',
        id,
        attempt,
      ),
      _ => false,
    };
  }
}
