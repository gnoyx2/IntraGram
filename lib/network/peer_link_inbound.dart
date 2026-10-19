part of 'peer_link.dart';

// 프레임이 도착할 때 일어나는 모든 것: 크기 게이트, outer 봉투 파싱, 버전/phase 검사, 핸드셰이크, 복호화
// PeerLink._onRawFrame의 pause/resume이 이 메서드를 한 번에 하나씩 완전히 끝난 뒤에만 부르게 보장해서
// _phase/_lastSeenSeq는 항상 직전 프레임까지 반영된 최신 값 (경합 없음)
// 프레임 타입마다 case 하나라 새 프레임 종류는 고칠 데가 한 군데
extension _PeerLinkInbound on PeerLink {
  Future<void> _onFrame(dynamic raw) async {
    if (_closed || raw is! String) return;

    // DoS 가드: 정상 프레임은 몇 KB라 상한을 넘는 건 고갈 시도로 보고 프레임을 버리고 링크를 죽임
    // unlimited 모드는 상한을 kFrameCeilingBytes까지 올림
    final frameCap = store.largeMessageMode == LargeMessageMode.unlimited
        ? kFrameCeilingBytes
        : kMaxFrameBytes;
    if (raw.length > frameCap) {
      await _shutdown();
      return;
    }

    final outer = InboundOuter.parse(raw);
    switch (outer) {
      case HelloOuter():
        await _onHelloOuter(outer);
      case WebHelloOuter():
        await _onWebHelloOuter(outer);
      case AuthOuter():
        await _onAuthOuter(outer);
      case EncOuter():
        await _onEncrypted(outer);
      case PlainOuter():
        if (_phase == _LinkPhase.web) {
          // 단일 인가 입구: 거부되면(null) dispatch도 relay도 안 함
          // 방 멤버에게 어떤 프레임을 중계할지는 레지스트리가 정하고, 방 멤버가 아니면 콜백이 null
          final authorized = _authorizeInner(outer.inner);
          if (authorized != null) _deliver(authorized);
        }
      case VersionMismatchOuter():
        // 평문으로 계속 진행하는 척하지 않고 닫음. 안내 줄은 종료가 내가 다이얼한 대화에만 남김
        // (모르는 기기가 연 연결에 남기면 아무 LAN 기기나 버전만 바꿔 빈 대화 타일을 쌓을 수 있음)
        _failReason = SystemEventKind.protocolVersionMismatch;
        await _shutdown();
      case MalformedOuter():
        break;
    }
  }

  // 인가된 프레임 하나를 local dispatch(typed)와 방 멤버 중계(정규화 wire, relay일 때만) 양쪽에 그대로 넘김
  void _deliver(_Authorized authorized) {
    if (authorized.local) _dispatch(authorized.inner);
    if (authorized.relay) onRoomFrame?.call(authorized.wire);
  }

  Future<void> _onHelloOuter(HelloOuter outer) async {
    if (_phase != _LinkPhase.awaitingHello) {
      // 이미 app/web으로 확정됐거나 처리 중인 링크의 후속 hello는 다운그레이드/재생 시도로 보고 닫음
      // identity/store 변경은 검증 성공 뒤에만 함
      await _shutdown();
      return;
    }
    _phase = _LinkPhase.handshaking;
    // 차단했거나 받지 않기로 한 기기: 키 합의 전에 닫음 (인바운드 임시 대화는 _failPeerHello가 치움)
    final refusal = refusePeer?.call(outer.peerId);
    if (refusal != null) {
      await _failPeerHello(refusal);
      return;
    }
    await _onPeerHello(outer);
  }

  Future<void> _onWebHelloOuter(WebHelloOuter outer) async {
    if (dialledByUs || _phase != _LinkPhase.awaitingHello) {
      // 우리가 다이얼한 앱 링크는 웹 게스트를 안 받음 (브라우저가 응답할 이유가 없음)
      // 이미 확정된 링크의 후속 web_hello도 닫음: 암호 링크를 평문으로 다운그레이드하지 않음
      await _shutdown();
      return;
    }
    final required = requiredWebToken?.call();
    if (required == null || !constantTimeEquals(outer.token ?? '', required)) {
      // 포털이 꺼져 있거나 토큰이 없거나 틀림: 채팅 접근 금지. 남은 임시 "peer"
      // 대화를 유령으로 안 남기고 지움 (_joinRoom 성공 경로와 대칭)
      store.wipeConversation(conversationId);
      await _shutdown();
      return;
    }
    _phase = _LinkPhase.web;
    _onWebHello(outer.alias);
  }

  void _onWebHello(String alias) {
    _handshakeWatchdog?.cancel();
    peerAlias = alias;
    peerPlatform = 'Web';
    transport = PeerTransport.web;

    // 브라우저 게스트는 X25519를 못 함. 이 링크는 LAN 위 평문
    _crypto?.destroy();
    _crypto = null;

    // 레지스트리가 이 링크를 공유 포털 룸으로 옮김: 이 콜백 뒤로 conversationId는 포털 룸을 가리킴
    // 대화 제목은 레지스트리가 관리(게스트 수 표시)해서 게스트 alias로
    // 안 덮어쓰고, alias는 link.peerAlias로 각 메시지에
    // 붙음
    onWebGuestHello?.call();

    store.updateConversation(
      conversationId,
      (c) =>
          c.copyWith(peerPlatform: peerPlatform, secure: false, online: true),
    );
    _flushPending();
  }

  Future<void> _onEncrypted(EncOuter frame) async {
    final crypto = _crypto;
    if (_phase != _LinkPhase.app || crypto == null || !crypto.isReady) return;
    // 리플레이/역행 프레임은 복호화 전에 버림 (변조 프레임과 동일 취급)
    // seq는 AEAD associated data로 인증돼서 공격자가 이 필드만 고쳐 통과시킬 수 없음
    if (frame.seq <= _lastSeenSeq) return;
    try {
      final inner = await crypto.open(
        nonceB64: frame.nonceB64,
        cipherB64: frame.cipherB64,
        macB64: frame.macB64,
        seq: frame.seq,
      );
      // 인증까지 통과한 진짜 프레임이 바로 다음 번호가 아니면 그 사이 프레임을 누가 버린 것 (보내는 쪽은
      // 번호를 빠짐없이 매김). 조용히 넘어가지 않고 링크를 닫음. 위조 프레임은 위에서 인증에 걸려 여기 못 옴
      if (frame.seq != _lastSeenSeq + 1) {
        await _shutdown();
        return;
      }
      // 복호화(= 인증) 성공한 프레임만 워터마크를 전진시킴 (위조된 높은 seq로 워터마크를 태워 진짜 후속 프레임을 막는 걸 방지)
      _lastSeenSeq = frame.seq;
      // 단일 인가 입구: 거부되면(null) dispatch도 relay도 안 함. 통과하면 같은 정규화 결과를 dispatch와
      // 방 멤버 중계(1:1 링크엔 콜백 null) 둘 다에 씀 (raw를 다시 안 섞음)
      final authorized = _authorizeInner(inner);
      if (authorized != null) _deliver(authorized);
    } on Object {
      // 나쁜 tag(변조/seq 위조/키 불일치)는 조용히 버림: 쓰레기를 재전송하는 LAN 공격자가 링크를 못 죽이게
    }
  }
}
