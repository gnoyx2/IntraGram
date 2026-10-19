part of 'peer_link.dart';

// 프레임 타입마다 case 하나 (디스패치 테이블 없음). 새 프레임 종류는 이 switch 한 군데만 고치면 됨
extension _PeerLinkDispatch on PeerLink {
  // 다른 대화의 메시지 id를 안다고(방 멤버라 relay로 봤거나 추측)
  // 그 메시지를 burn/react/read 시킬 수 있으면 안 됨:
  // 인증된 발신자라도 자기 대화 밖으론 못 나감
  bool _ownsMessage(String messageId) =>
      store.messageById(messageId)?.conversationId == conversationId;

  void _dispatch(InboundInner inner) {
    switch (inner) {
      case MessageInner():
        _ingestMessage(inner);
      case AckInner():
        _unacked.remove(inner.id);
        if (_ownsMessage(inner.id)) {
          store.advanceDelivery(inner.id, DeliveryState.delivered);
        }
      case ReadInner():
        _unacked.remove(inner.id);
        if (_ownsMessage(inner.id)) {
          store.applyReadReceipt(inner.id, inner.peerId ?? peerAlias);
        }
      case VerifyInner():
        // 내가 이미 로컬에서 눌러놓고 피어의 확인만 기다리던 참이면 방금 양쪽 다 확인된 것이라 완료 알림을 띄움
        // 아직 안 눌렀으면 조용히 peerVerified만 적음
        // 방이면 이 verify는 이 링크 상대(remotePeerId) 한 명만의 것: 대화 전체 verified가 아니라
        // 그 멤버 슬롯(RoomMember)만 갱신해야 안 섞임
        final conversation = store.conversation(conversationId);
        final peerId = remotePeerId;
        if (conversation != null && conversation.isRoom && peerId != null) {
          final wasMutual = conversation.members[peerId]?.verified ?? false;
          store.setRoomMemberPeerVerified(conversationId, peerId);
          final nowMutual =
              store.conversation(conversationId)?.members[peerId]?.verified ??
              false;
          if (!wasMutual && nowMutual) {
            store.addSystemMessage(
              conversationId,
              const SystemEvent(SystemEventKind.mutuallyVerified),
            );
          }
        } else {
          final wasMutual = conversation?.verified ?? false;
          store.setPeerVerified(conversationId);
          final nowMutual =
              store.conversation(conversationId)?.verified ?? false;
          if (!wasMutual && nowMutual && !_carried) {
            store.addSystemMessage(
              conversationId,
              const SystemEvent(SystemEventKind.mutuallyVerified),
            );
          }
        }
      case RenameInner(:final alias, :final peerId):
        // peerId는 _authorizeInner/_stampActor가 이미 확정함
        // (멤버면 호스트가 relay 단계에서 origin 멤버의 진짜 identity로
        // 도장,
        // 그 외는 이 링크의 인증된 identity). 여기서 다시 안 따짐
        final conversation = store.conversation(conversationId);
        if (conversation != null && conversation.isRoom) {
          store.renameRoomMember(conversationId, peerId, alias);
          // peerId가 이 링크 상대 자신이면(방에서 호스트거나 그 멤버) hostAlias 표시도 같이 맞춤
          // 릴레이로 온 다른 멤버 것은 remotePeerId와 달라서 안 걸림
          if (peerId == remotePeerId && conversation.hostAlias != null) {
            store.updateConversation(
              conversationId,
              (c) => c.copyWith(hostAlias: alias),
            );
          }
        } else {
          store.updateConversation(
            conversationId,
            (c) => c.copyWith(peerAlias: alias),
          );
        }
      case BurnInner():
        if (_ownsMessage(inner.id)) store.burnMessage(inner.id);
      case ScreenshotInner():
        store.addSystemMessage(
          conversationId,
          SystemEvent(
            SystemEventKind.screenshotByPeer,
            inner.from ?? peerAlias,
          ),
        );
      case TypingInner():
        store.setPeerTyping(conversationId, typing: inner.active);
      case ReactInner():
        if (_ownsMessage(inner.id)) {
          store.applyReaction(
            inner.id,
            inner.peerId ?? peerAlias,
            inner.emoji,
            on: inner.on,
          );
        }
      case RoomJoinInner():
        // count까지 같이 옴: label만 받으면 memberCount가
        // 다음 room_state까지 0에 고정돼 읽음 카운트 배지가
        // 틀림
        // 내(멤버) 쪽에서 방은 host 한 명짜리 멤버 맵이라 SAS/검증도 host<->나
        // 세션 것만 있으면 됨 (hello가 끝난 뒤라 remotePeerId/sasDigits
        // 있음)
        final hostPeerId = remotePeerId;
        if (hostPeerId != null) {
          store.upsertRoomMember(
            conversationId,
            hostPeerId,
            alias: peerAlias,
            platform: peerPlatform,
          );
          final sas = sasDigits;
          if (sas != null) {
            store.setRoomMemberSas(conversationId, hostPeerId, sas);
          }
          // 승격된 1:1이면 같은 세션이라 이미 맞춘 코드를 다시 맞출 이유가 없음 (호스트 쪽 _promoteToRoom과 대칭)
          final prior = store.conversation(conversationId);
          if (prior?.localVerified ?? false) {
            store.setRoomMemberLocalVerified(conversationId, hostPeerId);
          }
          if (prior?.peerVerified ?? false) {
            store.setRoomMemberPeerVerified(conversationId, hostPeerId);
          }
        }
        store.updateConversation(
          conversationId,
          (c) => c.copyWith(
            isRoom: true,
            localVerified: false,
            peerVerified: false,
            hostAlias: peerAlias,
            // 인가가 확정한 호스트의 인증된 peerId: 이후 room_join/room_state는
            // 이 링크 상대에게서만 받음 (alias는 표시용)
            hostPeerId: hostPeerId,
            roomRecipientIds: List<String>.unmodifiable(inner.peers),
            peerAlias: roomTitle(inner.count),
            memberCount: inner.count,
            // 1:1에서 켜 둔 자동 수락이 평문 방으로 안 이어지게 함 (호스트 쪽 승격과 같은 규칙)
            // 아니면 방의 아무 멤버가 낸 파일이 탭 없이 저장됨
            autoAcceptFiles: false,
          ),
        );
        store.addSystemMessage(
          conversationId,
          SystemEvent(SystemEventKind.joinedRoom, peerAlias),
        );
        onRoomRoster?.call(inner.peers);
      case RoomStateInner():
        // peerAlias(방 제목)도 count에서 다시 뽑아 같이 갱신:
        // count만 갱신하면 방금 합류한 멤버 말곤 바뀐 인원수를 제목에서
        // 못 봄
        store.updateConversation(
          conversationId,
          (c) => c.copyWith(
            peerAlias: roomTitle(inner.count),
            memberCount: inner.count,
            roomRecipientIds: List<String>.unmodifiable(inner.peers),
          ),
        );
        onRoomRoster?.call(inner.peers);
        if (inner.joined != null) {
          store.addSystemMessage(
            conversationId,
            SystemEvent(SystemEventKind.memberJoined, inner.joined),
          );
        }
        if (inner.left != null) {
          store.addSystemMessage(
            conversationId,
            SystemEvent(SystemEventKind.memberLeft, inner.left),
          );
        }
      // 파일 전송 프레임은 _PeerLinkDispatchFile로 위임
      case FileOfferInner():
        _dispatchFileOffer(inner);
      case FileAcceptInner():
        _dispatchFileAccept(inner);
      case FileRejectInner():
        _dispatchFileReject(inner);
      case FileCancelInner():
        _dispatchFileCancel(inner);
      case FileReceivedInner():
        _dispatchFileReceived(inner);
      case FileRetryInner():
        _dispatchFileRetry(inner);
      case FileUnavailableInner():
        _dispatchFileUnavailable(inner);
      // 인가 입구(_authorizeInner)가 이 둘은 이미 걸렀고, 전수 switch를 위한 자리일 뿐
      case MalformedInner() || UnknownInner():
        break;
    }
  }

  void _ingestMessage(MessageInner inner) {
    // DoS 가드: 크기 넘는 텍스트는 스토어에 절대 안 들어옴
    // 한계: unlimited 모드는 이 인라인 가드를 걷어내고 프레임 레벨 kFrameCeilingBytes만
    // 남아서 진짜 거대 페이로드는 여전히 링크를 끊음
    if (store.largeMessageMode != LargeMessageMode.unlimited &&
        utf8.encode(inner.text).length > kMaxInlineMessageBytes) {
      return;
    }
    // 확인을 못 받은 상대가 같은 id로 다시 보낸 것: 확인만 다시 돌려주고 안 읽은 수는 그대로
    if (store.messageById(inner.id) != null) {
      if (_ownsMessage(inner.id)) {
        unawaited(deliverRawInner(InnerFrame.ack(inner.id)));
      }
      return;
    }

    store.setPeerTyping(conversationId, typing: false);
    store.addMessage(
      EphemeralMessage(
        id: inner.id,
        conversationId: conversationId,
        direction: MessageDirection.incoming,
        kind: MessageKind.text,
        senderAlias: inner.from ?? peerAlias,
        senderPeerId: inner.peerId ?? peerAlias,
        createdAt: DateTime.now(),
        text: inner.text,
        replyToId: inner.replyToId,
        ttlSeconds: inner.ttlSeconds.clamp(0, 24 * 3600),
        delivery: DeliveryState.sent,
      ),
    );
    // 받았다는 확인만 돌려줌. 못 보내도 상대 쪽이 sent로 남을 뿐이라 링크는 안 닫음
    if (_ownsMessage(inner.id)) {
      unawaited(deliverRawInner(InnerFrame.ack(inner.id)));
    }
    store.bumpUnread(conversationId);
  }
}
