part of 'peer_link.dart';

// 링크의 방 역할. wire의 hostAlias·pid 주장은 권한 판단에 절대 안 씀: registry가 검증한 구조로 표시하거나 정당한 room_join을 인가할 때만 바뀜
enum _RoomLinkRole { direct, localHostMember, remoteHost, webGuest }

// 인가를 통과한 프레임 하나. 로컬 dispatch는 inner, 중계는 정규화한 wire만 씀 (같은 결과 하나라 로컬에서 거부한 게 중계로 새지 않음).
// relay가 false면 나만 볼 프레임
class _Authorized {
  const _Authorized(
    this.inner,
    this.wire, {
    required this.local,
    required this.relay,
  });
  final InboundInner inner;
  final Map<String, dynamic> wire;
  final bool local;
  final bool relay;
}

// 역할·발신자·소속 검사와 정규화 맵 생성: 로컬 dispatch와 중계 앞의 단일 입구. 파싱 실패·모르는 kind도 여기서 거부 (아는 kind만 통과)
extension _PeerLinkAuthorization on PeerLink {
  _Authorized? _authorizeInner(Map<String, dynamic> raw) {
    final parsed = InboundInner.fromJson(raw);
    final routedControl = _routedRoomFileControl(parsed);
    final permitted = _authorize(parsed, routedControl);
    if (permitted == null) {
      _refuseDirectedOffer(parsed);
      return null;
    }
    final wire = _canonicalWire(raw);
    final inner = InboundInner.fromJson(wire);
    if (inner is MalformedInner || inner is UnknownInner) return null;
    final directed = parsed is FileOfferInner && parsed.to != null;
    final local = !routedControl && (!directed || parsed.to == identity.peerId);
    final relay = directed
        ? _roomRole == _RoomLinkRole.localHostMember && !local
        : permitted;
    return _Authorized(inner, wire, local: local, relay: relay);
  }

  // 호스트로서 멤버의 대상 지정 offer를 거부했으면 그 멤버에게 그 수신자 몫이 접혔다고 알림 (조용히 버리면 발신자가 영영 기다림)
  void _refuseDirectedOffer(InboundInner parsed) {
    if (parsed is! FileOfferInner ||
        _roomRole != _RoomLinkRole.localHostMember) {
      return;
    }
    final target = parsed.to;
    if (target == null) return;
    unawaited(
      sendOfferRefusal(parsed.id, attemptId: parsed.attempt, targetId: target),
    );
  }

  // null이면 거부, 아니면 방 멤버에게 중계해도 되는지. sealed 전수 switch라 새 프레임 종류를 안 넣으면 컴파일 에러
  bool? _authorize(InboundInner inner, bool routedControl) => switch (inner) {
    MessageInner() ||
    TypingInner() ||
    ScreenshotInner() ||
    VerifyInner() ||
    RenameInner() => true,
    // ack는 바로 앞 홉의 수신 확인이라 방에 중계하지 않음
    AckInner(:final id) => _ownsMessage(id) ? false : null,
    ReadInner(:final id) ||
    ReactInner(:final id) => _ownsMessage(id) ? true : null,
    BurnInner(:final id) => _mayBurn(id) ? true : null,
    RoomJoinInner() ||
    RoomStateInner() => _authorizeRoomControl(inner) ? false : null,
    FileOfferInner() => _authorizeFileOffer(inner) ? true : null,
    FileAcceptInner(:final id, :final attempt, :final peerId) =>
      routedControl
          ? true
          : _authorizeFileControl(
              'file_accept',
              id,
              attempt,
              _resolveActor(peerId),
            ),
    FileRejectInner(:final id, :final attempt, :final peerId) =>
      routedControl
          ? true
          : _authorizeFileControl(
              'file_reject',
              id,
              attempt,
              _resolveActor(peerId),
            ),
    FileReceivedInner(:final id, :final attempt, :final peerId) =>
      routedControl
          ? true
          : _authorizeFileControl(
              'file_received',
              id,
              attempt,
              _resolveActor(peerId),
            ),
    FileRetryInner(:final id, :final attempt, :final peerId) =>
      routedControl
          ? true
          : _authorizeFileControl(
              'file_retry',
              id,
              attempt,
              _resolveActor(peerId),
            ),
    FileCancelInner(:final id, :final attempt, :final peerId) =>
      routedControl
          ? true
          : _authorizeFileControl(
              'file_cancel',
              id,
              attempt,
              _resolveActor(peerId),
            ),
    FileUnavailableInner(:final id) =>
      _authorizeFileUnavailable(id) ? false : null,
    MalformedInner() || UnknownInner() => null,
  };

  // room_join/room_state는 호스트 → 멤버 방향이고 링크 상대가 그 방의 확정된 호스트일 때만 통과. 내가 호스트인 링크·방에선 늘 거부.
  // 1:1을 방으로 바꾸는 첫 room_join은 우리가 다이얼했거나 양쪽이 SAS를 확인한 상대만 받고 hostPeerId로 못박음.
  // 이미 방이면 확정된 호스트 링크의 갱신만 받음
  bool _authorizeRoomControl(InboundInner inner) {
    if (_phase != _LinkPhase.app) return false;
    final linkPeerId = remotePeerId;
    if (linkPeerId == null) return false;
    if (_roomRole == _RoomLinkRole.localHostMember ||
        _roomRole == _RoomLinkRole.webGuest) {
      return false;
    }
    final conversation = store.conversation(conversationId);
    if (conversation == null) return false;
    if (!conversation.isRoom) {
      if (inner is! RoomJoinInner) return false;
      if (conversation.peerId != linkPeerId) return false;
      if (!dialledByUs && !conversation.verified) return false;
      _roomRole = _RoomLinkRole.remoteHost;
      return true;
    }
    if (conversation.hostAlias == null) return false;
    final hostPeerId = conversation.hostPeerId;
    if (hostPeerId != null && hostPeerId != linkPeerId) return false;
    if (hostPeerId == null && !conversation.members.containsKey(linkPeerId)) {
      return false;
    }
    _roomRole = _RoomLinkRole.remoteHost;
    return true;
  }

  // 모두에게서 지우기는 쓴 사람만. 타이머 메시지는 양쪽 만료를 맞추는 신호라 누구나 되고, 호스트가 중계한 방 프레임은 호스트가 이미 검사함
  bool _mayBurn(String id) {
    final message = store.messageById(id);
    if (message == null || message.conversationId != conversationId) {
      return false;
    }
    if (message.ttlSeconds > 0 || _trustsRelayedActor) return true;
    return !message.isMine &&
        message.senderPeerId == (remotePeerId ?? peerAlias);
  }

  // 내가 남의 방 멤버라서 wire의 from/pid를 호스트가 원래 멤버 신원으로 이미 도장 찍었는가
  bool get _trustsRelayedActor {
    final conversation = store.conversation(conversationId);
    return (conversation?.isRoom ?? false) && conversation?.hostAlias != null;
  }

  // 발신자 peerId: 위 경우만 wire 값을 쓰고 나머지는 이 링크의 인증된 신원 (pid 위조로 다른 멤버 사칭 차단)
  String _resolveActor(String? wirePeerId) {
    final linkActorId = remotePeerId ?? peerAlias;
    return _trustsRelayedActor ? (wirePeerId ?? linkActorId) : linkActorId;
  }
}
