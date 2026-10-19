part of 'peer_link.dart';

// 링크의 방 역할. wire가 주장하는 hostAlias/pid는 권한 판단에 절대 못 씀: registry가 검증된 topology로
// markHostedMember/markWebGuest를 부를 때나 이 파일이 정당한 room_join을 인가할 때만 바뀜
enum _RoomLinkRole { direct, localHostMember, remoteHost, webGuest }

// 인가를 통과한 프레임 하나. local dispatch는 inner(typed)만, 방 멤버 중계는 wire(정규화된 map)만 씀
// 둘 다 같은 하나의 인가/정규화 결과라서 로컬에서 거부한 프레임이 relay로 새거나 원본 raw가 다시 섞이는 일이 없음
// relay가 false면 이 링크 상대가 나한테 보낸(나만 볼) 프레임이라 중계 안 함
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

// kind별로 wire에 실을 수 있는 필드: 정규화 map은 이 목록의 키만
// 복사함 (공격자가 끼운 여분 키는 dispatch/relay에 안 넘어감)
const Map<String, Set<String>> _kInnerWireKeys = <String, Set<String>>{
  'msg': {'id', 'text', 'ttl', 'ts', 're'},
  'ack': {'id'},
  'read': {'id'},
  'verify': <String>{},
  'rename': {'alias'},
  'burn': {'id'},
  'screenshot': <String>{},
  'typing': {'on'},
  'react': {'id', 'emoji', 'on'},
  'room_join': {'count', 'peers'},
  'room_state': {'count', 'joined', 'left', 'peers'},
  'file_offer': {
    'id', 'at', 'md', 'name', 'size', 'mime', 'sh', 'sp', //
    'th', 'pv', 'bid', 'ttl', 'tok', 'vc', 'ec', 'to', 'dg',
  },
  'file_accept': {'id', 'at', 'tok'},
  'file_reject': {'id', 'at'},
  'file_cancel': {'id', 'at'},
  'file_received': {'id', 'at'},
  'file_retry': {'id', 'at'},
  'file_unavailable': {'id', 'at', 'to'},
};

// 발신자(from/pid)를 링크의 인증된 신원으로 도장 찍는 kind들
const Set<String> _kActorKinds = <String>{
  'msg',
  'read',
  'react',
  'screenshot',
  'typing',
  'rename',
  'file_offer',
  'file_accept',
  'file_reject',
  'file_cancel',
  'file_received',
  'file_retry',
};

// role/actor/ownership 검증과 canonical map 생성: local dispatch와 relay
// 둘 다에 들어가기 전의 단일 입구 (결과 하나만 _dispatch와 onRoomFrame에 전달하고
// 거부(null)면 둘 다 안 불림). 파싱 실패(MalformedInner)와 알 수 없는 kind(UnknownInner)도
// 여기서 거부: 지원하는 kind만 통과하는 default-deny
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

  // 호스트로서 방 멤버의 대상 지정 offer를 거부했으면 그 멤버에게 그
  // 수신자 몫이 접혔다고 알림 (조용히 버리면 발신자가 그 수신자를 영영 기다림)
  // 대상이 없는 offer나 다른 프레임은 알릴 대상이 없어 조용히 버림
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

  // null이면 거부, 아니면 "방 멤버에게 중계해도 되는가". switch가 sealed
  // 타입 전수 검사라 새 프레임 종류를 추가하고 여기를 안 고치면 컴파일 에러
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

  // room_join/room_state 권한: 호스트 -> 멤버 방향만 있고 이 링크 상대가 그 방의 확정된 호스트일 때만 통과
  // - 내가 호스트인 링크나 방에서 오는 건 항상 거부 (호스트가 만드는 프레임이지 받는 게 아님)
  // - 1:1이 방으로 바뀌는 최초 room_join은 인증된 앱 피어 링크가 그 상대이고 우리가 합류를 요청했거나(다이얼한
  // 링크) 사용자가 SAS로 양쪽 검증한 경우만 허용하고
  // hostPeerId로 못박음 (수신 frame의 주장만으론 확정 안 함)
  // - 이미 방이면 확정된 hostPeerId 링크의 갱신만 허용
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

  // 모두에게서 지우기는 쓴 사람만. 타이머 메시지는 양쪽 만료를 맞추는 신호라 누구나 보낼 수 있고,
  // 호스트가 중계해 준 방 프레임은 호스트가 이미 이 검사를 함
  bool _mayBurn(String id) {
    final message = store.messageById(id);
    if (message == null || message.conversationId != conversationId) {
      return false;
    }
    if (message.ttlSeconds > 0 || _trustsRelayedActor) return true;
    return !message.isMine &&
        message.senderPeerId == (remotePeerId ?? peerAlias);
  }

  // 내가 호스트가 중계한 방의 멤버인가 (= wire의 from/pid를
  // 호스트가 origin 멤버의 인증된 identity로 이미 도장 찍었는가)
  bool get _trustsRelayedActor {
    final conversation = store.conversation(conversationId);
    return (conversation?.isRoom ?? false) && conversation?.hostAlias != null;
  }

  // 발신자로 신뢰할 peerId: 위 경우엔 wire 값을 쓰고, 그 외(직접
  // 링크, 또는 내가 호스트로서 멤버에게 직접 받음)는 wire 주장을 전부
  // 무시하고 이 링크의 인증된 identity를 씀 (pid 위조로 다른 멤버를 사칭해 relay되는 걸 차단)
  String _resolveActor(String? wirePeerId) {
    final linkActorId = remotePeerId ?? peerAlias;
    return _trustsRelayedActor ? (wirePeerId ?? linkActorId) : linkActorId;
  }

  // kind별 허용 키만 복사하고(null 값 제외), 발신자 kind면
  // from/pid를 인증된 값으로 도장 찍음. raw를 통째로 펼치지
  // 않음
  Map<String, dynamic> _canonicalWire(Map<String, dynamic> raw) {
    final kind = raw['k'] as String;
    final allowed = _kInnerWireKeys[kind] ?? const <String>{};
    final wire = <String, dynamic>{
      'k': kind,
      for (final key in allowed)
        if (raw[key] != null) key: raw[key],
    };
    if (!_kActorKinds.contains(kind)) return wire;
    final wireFrom = _trustsRelayedActor
        ? wireText(raw['from'], maxUtf8Bytes: 256)
        : null;
    wire['from'] = wireFrom ?? peerAlias;
    wire['pid'] = _resolveActor(wireId(raw['pid']));
    return wire;
  }
}
