part of 'peer_link.dart';

// 프레임이 들어올 때: 크기 게이트, 바깥 봉투 파싱, 버전·phase 검사, 핸드셰이크, 복호화. _onRawFrame이 한 번에 하나씩만 불러서
// _phase·_lastSeenSeq는 늘 직전 프레임까지 반영됨
extension _PeerLinkInbound on PeerLink {
  Future<void> _onFrame(dynamic raw) async {
    if (_closed || raw is! String) return;

    // 정상 프레임은 몇 KB라 상한 넘으면 고갈 시도로 보고 끊음 (unlimited 모드는 kFrameCeilingBytes까지)
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
          // 거부(null)면 dispatch도 중계도 안 함
          final authorized = _authorizeInner(outer.inner);
          if (authorized != null) _deliver(authorized);
        }
      case VersionMismatchOuter():
        // 평문 통신을 이어가지 않고 연결을 닫음. 안내 메시지는 직접 다이얼한 대화에만 남김 (임의 기기가 버전만 바꿔 빈 대화를 누적하지 못하게 막음)
        _failReason = SystemEventKind.protocolVersionMismatch;
        await _shutdown();
      case MalformedOuter():
        break;
    }
  }

  void _deliver(_Authorized authorized) {
    if (authorized.local) _dispatch(authorized.inner);
    if (authorized.relay) onRoomFrame?.call(authorized.wire);
  }

  Future<void> _onHelloOuter(HelloOuter outer) async {
    if (_phase != _LinkPhase.awaitingHello) {
      // 이미 확정됐거나 처리 중인 링크의 두 번째 hello는 다운그레이드·재생 시도라 닫음
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
      // 우리가 다이얼한 링크는 웹 게스트일 리 없고, 확정된 링크의 web_hello는 평문 다운그레이드라 닫음
      await _shutdown();
      return;
    }
    final required = requiredWebToken?.call();
    if (required == null || !constantTimeEquals(outer.token ?? '', required)) {
      // 포털 비활성화·토큰 불일치 시 연결을 종료함. 임시 'peer' 대화가 남지 않도록 삭제함
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

    // 브라우저는 X25519 핸드셰이크를 지원하지 않으므로 이 링크는 LAN 평문으로 통신함
    _crypto?.destroy();
    _crypto = null;

    // 레지스트리가 이 링크를 포털 방으로 옮김 (이 뒤로 conversationId는 포털 방). 제목은 레지스트리가 관리해서 안 덮음
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
    // 리플레이·역행 프레임은 복호화 전에 버림. seq는 AAD로 인증돼서 이 필드만 고쳐 통과시킬 수 없음
    if (frame.seq <= _lastSeenSeq) return;
    try {
      final inner = await crypto.open(
        nonceB64: frame.nonceB64,
        cipherB64: frame.cipherB64,
        macB64: frame.macB64,
        seq: frame.seq,
      );
      // 인증까지 통과한 진짜 프레임이 바로 다음 번호가 아니면 사이 프레임을 누가 버린 것: 조용히 넘어가지 않고 닫음 (위조 프레임은 위에서 걸림)
      if (frame.seq != _lastSeenSeq + 1) {
        await _shutdown();
        return;
      }
      // 인증 통과한 프레임만 워터마크를 갱신함 (위조된 큰 seq로 워터마크를 조작해 정상 프레임 수신을 방해하는 행위를 방지함)
      _lastSeenSeq = frame.seq;
      // 거부(null)면 dispatch도 중계도 안 함. 통과하면 같은 정규화 결과를 둘 다에 씀
      if (inner['k'] == 'org_cred') {
        unawaited(
          _receiveOrgCredential(
            _canonicalWire(inner),
          ).catchError((Object _) {}),
        );
        return;
      }
      final authorized = _authorizeInner(inner);
      if (authorized != null && await _verifyRoomIntegrity(authorized)) {
        if (!_closed && store.conversation(conversationId) != null) {
          _deliver(authorized);
        }
      }
    } on Object {
      // 유효하지 않은 tag는 조용히 무시함 (비정상 데이터를 보내는 LAN 공격자가 링크를 강제 종료하지 못하게 막음)
    }
  }
}
