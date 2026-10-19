part of 'peer_link.dart';

// _PeerLinkAuthorization의 파일 프레임 절반: file_offer와
// accept/reject/cancel/received/retry를 dispatch 전에 검사 (거부할
// 프레임이 onRoomFrame으로 흘러가면 실패라서 충돌/downgrade/mode 검사가 전부 여기
// 인가 입구에 있음)
extension _PeerLinkAuthorizationFile on PeerLink {
  // 이 offer를 받아줄 수 있는가: 방(공유 키 없음)은 항상 평문, 1:1은 항상 암호화 (어긋나면
  // downgrade/풀 수 없는 offer라 거부). pull은 방 offer나 1:1 음성 메시지만
  // 같은 id의 기존 전송이 있으면 같은 발신자/같은 메타데이터의 재전송일
  // 때만 통과 (다른 대화, 다른 발신자, 내 아웃고잉 id 충돌은 거부)
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
    // 웹 게스트가 밝힌 원본 주소도 자기 링크 주소여야 함: 호스트 사용자가 수락할 때 게스트가 고른 임의의 사설 주소에서 당겨오지 않게
    // (브라우저는 서버가 아니라 정상 offer엔 주소가 없음)
    if (_roomRole == _RoomLinkRole.webGuest &&
        offer.srcHost != null &&
        offer.srcHost != remoteHost) {
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

  // 기존 인커밍 전송의 재offer가 정당한가: attempt가 같으면 멱등 재전송이고, 다르면 보내는 쪽이 수락 전(offered)이거나
  // 실패한(failed) 전송을 새 attempt/토큰으로 다시 협상하는 경우만 (진행 중/완료된 전송을 도중에 갈아치우지 못함)
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
    if (existing.fileName != offer.name ||
        existing.totalBytes != offer.size ||
        existing.voice != offer.voice ||
        existing.encrypted != offer.enc ||
        existing.digest != offer.digest ||
        existing.mode != mode) {
      return false;
    }
    // 호스트의 수신 상태는 다른 멤버의 독립 attempt를 막는 근거가 아님:
    // 인증된 같은 발신자의 동일 파일인지만 확인하고 대상별 시도는 라우터가 관리함
    if (routed || existing.attemptId == offer.attempt) return true;
    return existing.state == TransferState.offered ||
        existing.state == TransferState.failed;
  }

  // accept/reject/cancel/received/retry는 이 대화의 전송만 가리켜야 함 (다른
  // 방/모르는 id는 거부, 프로빙도 못 함). 반환값은 relay 여부: 내가 보내는 쪽(아웃고잉)이면
  // 상대가 나한테 보낸 프레임이라 중계 안 하고, 호스트로서 두 멤버 사이를 중계하는 경우만 중계함. 현재
  // attempt/수신자 검사는 상태를 아는 registry 처리기가 하고 거부된 프레임은 상태를 안 건드림
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
    // 인커밍은 이 링크의 store가 현재 attempt를 앎. 오래된
    // 제어 프레임은 local 처리뿐 아니라 relay에도 실으면 안
    // 됨
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

  // 호스트가 보낸 file_unavailable: 이 링크 상대가 이 방의 확정된 호스트이고(room_join이
  // 인가한 remoteHost 역할 + hostPeerId가 이 링크의 인증된 peerId와 같음)
  // 이 대화의 내 아웃고잉 전송을 가리킬 때만 통과. 일반 멤버, 웹 게스트, 1:1 상대, 내가 호스트인
  // 링크의 위조는 전부 거부하고 중계도 안 함. 수신자/현재 attempt 검사는 registry가 함
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

  // 호스트로서 멤버 링크에서 받은 accept/reject/cancel/received/retry가
  // registry가 등록한 (전송 id, attempt) 경로의
  // 인증된 대상(cancel은 발신자도)에게서 온 것인가 (PeerLink.authorizeRoomFileControl)
  // 맞으면 내 것이 아니라 경로 반대편 멤버 몫이라 로컬 dispatch 없이 중계만 됨
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
