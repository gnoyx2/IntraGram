part of 'peer_link.dart';

extension _PeerLinkDispatch on PeerLink {
  // 인증된 상대라도 자기 대화 밖 메시지는 못 건드림 (방 멤버라 다른 대화 id를 알아도)
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
        // 방이면 이 verify는 링크 상대 한 명 몫이라 그 멤버 슬롯만 갱신함 (대화 전체 verified랑 안 섞임)
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
        // peerId는 인가 단계가 이미 확정함 (방 멤버면 호스트가 원래 멤버 신원으로 도장, 아니면 이 링크 신원)
        final conversation = store.conversation(conversationId);
        if (conversation != null && conversation.isRoom) {
          store.renameRoomMember(conversationId, peerId, alias);
          // 링크 상대 자신이 이름을 바꿨으면 hostAlias 표시도 같이 맞춤 (중계된 다른 멤버 것은 안 걸림)
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
        if (_ownsMessage(inner.id)) {
          store.burnMessage(inner.id, cause: BurnCause.peerRequest);
        }
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
        // count도 같이 옴 (안 그러면 다음 room_state까지 인원이 0이라 읽음 배지가 틀림). 멤버 쪽 방은 호스트 한 명짜리
        // 멤버 맵이라 SAS·검증도 호스트와 나 사이 것만 있으면 됨
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
          // 승격된 1:1이면 같은 세션이라 이미 맞춘 코드를 이어 감 (호스트 쪽 _promoteToRoom과 대칭)
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
            // 인가가 확정한 호스트 peerId: 이후 room_join/room_state는 이 링크 상대한테서만 받음
            hostPeerId: hostPeerId,
            roomRecipientIds: List<String>.unmodifiable(inner.peers),
            peerAlias: roomTitle(inner.count),
            memberCount: inner.count,
            // 1:1에서 켠 자동 수락이 평문 방으로 안 이어지게 함 (안 그러면 아무 멤버 파일이 탭 없이 저장됨)
            autoAcceptFiles: false,
          ),
        );
        store.addSystemMessage(
          conversationId,
          SystemEvent(SystemEventKind.joinedRoom, peerAlias),
        );
        onRoomRoster?.call(inner.peers);
      case RoomStateInner():
        // 방 제목도 count로 다시 만듦 (count만 바꾸면 제목 인원수가 안 바뀜)
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
      // 인가 입구가 이미 거름. 전수 switch용 자리
      case MalformedInner() || UnknownInner():
        break;
    }
  }

  void _ingestMessage(MessageInner inner) {
    // 너무 긴 글은 store에 안 넣음 (unlimited 모드는 프레임 상한만 남음)
    if (store.largeMessageMode != LargeMessageMode.unlimited &&
        utf8.encode(inner.text).length > kMaxInlineMessageBytes) {
      return;
    }
    // 확인을 받지 못한 상대가 동일한 id로 재전송한 경우: 확인(ack)만 다시 회신하고 안 읽은 개수는 유지함
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
