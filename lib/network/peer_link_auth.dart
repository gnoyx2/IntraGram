part of 'peer_link.dart';

// 앱 피어 핸드셰이크 + 신원 증명(프로토콜 v7, 커밋-후-공개)
// 1) 다이얼러 hello: 신원키 + 임시키 커밋 (임시키 자체는 아직 안 보냄)
// 2) 리스너 hello: 신원키 + 임시키 + 서명(커밋·리스너 임시키·양쪽 신원키)
// 3) 다이얼러 auth: 임시키 공개 + 서명(양쪽 임시키·양쪽 신원키)
// 리스너는 2)를 보낼 때 다이얼러 임시키를 모르고 다이얼러 키는 1)에서 이미 묶여서, 어느 자리의
// 중간자도 상대 키를 본 뒤 6자리 SAS를 맞추는 키를 고를 수 없음
// 증명 전엔 상대 peerId/이름을 링크에도 store에도 반영 안 함
extension _PeerLinkAuth on PeerLink {
  String _helloFrame(CryptoSession crypto, Uint8List idKey, {String? sig}) =>
      OuterFrame.hello(
        peerId: identity.peerId,
        alias: identity.alias,
        platform: identity.platform,
        identityKeyB64: base64.encode(idKey),
        publicKeyB64: dialledByUs ? null : crypto.publicKeyBase64,
        commitmentB64: dialledByUs
            ? base64.encode(
                ephemeralCommitment(
                  ephemeral: crypto.publicKey,
                  identityKey: idKey,
                ),
              )
            : null,
        signatureB64: sig,
        port: localPort,
      );

  // 증명 실패한 앱 피어 hello: 인바운드면 방금 만든 placeholder 대화도 치움 (다이얼한 링크의 대화는 사용자 것이라 둠)
  // 방으로 옮겨진 링크의 대화(방 기록)는 절대 안 지움
  Future<void> _failPeerHello([
    SystemEventKind reason = SystemEventKind.handshakeFailed,
  ]) {
    _failReason ??= reason;
    final inRoom = store.conversation(conversationId)?.isRoom ?? false;
    if (!dialledByUs && !inRoom) store.wipeConversation(conversationId);
    return _shutdown();
  }

  // 역할과 무관한 구조 검사 (서명 전에 거름). 밝힌 peerId는 신원 키의 해시여야 하고, 다이얼한 링크는
  // 기대한 peerId여야 함 (DHCP 재할당 등으로 다른 기기가 있으면 예전 대화에 조용히 안 이어붙임)
  // 내 peerId를 밝히는 hello는 중간자가 내 hello를 되돌린(반사) 것이고, 작은 위수 점 키는 서명 위조가
  // 가능해서 신원 키가 될 수 없음
  bool _acceptableHello(HelloOuter hello) =>
      hello.peerId != identity.peerId &&
      !isSmallOrderKey(hello.identityKey) &&
      peerIdOfKey(hello.identityKey) == hello.peerId &&
      (expectedPeerId == null || expectedPeerId == hello.peerId);

  Future<void> _onPeerHello(HelloOuter hello) async {
    final crypto = _crypto;
    final ownKey = identity.publicKey;
    // 키 없는 신원은 증명을 못 함. 기대한 peerId가 아니면 이 주소에 다른 기기가 있는 것(DHCP 재할당 등)
    if (crypto == null || ownKey == null || !_acceptableHello(hello)) {
      final elsewhere = (expectedPeerId ?? hello.peerId) != hello.peerId;
      await _failPeerHello(
        elsewhere
            ? SystemEventKind.peerMismatch
            : SystemEventKind.handshakeFailed,
      );
      return;
    }
    if (dialledByUs) {
      await _onListenerHello(hello, crypto, ownKey);
    } else {
      await _onDialerHello(hello, crypto, ownKey);
    }
  }

  // 다이얼러 쪽: 리스너는 임시키와, 내 커밋에 묶인 서명을 보내야 함
  Future<void> _onListenerHello(
    HelloOuter hello,
    CryptoSession crypto,
    Uint8List ownKey,
  ) async {
    final peerEphemeral = hello.ephemeralKey;
    final signature = hello.signature;
    final ownEphemeral = crypto.publicKey;
    if (peerEphemeral == null ||
        hello.commitment != null ||
        signature == null ||
        !await verifyAuth(
          transcript: listenerTranscript(
            dialerCommitment: ephemeralCommitment(
              ephemeral: ownEphemeral,
              identityKey: ownKey,
            ),
            listenerEphemeral: peerEphemeral,
            dialerKey: ownKey,
            listenerKey: hello.identityKey,
          ),
          signature: signature,
          signerKey: hello.identityKey,
        )) {
      await _failPeerHello();
      return;
    }
    if (!await _agree(crypto, peerEphemeral)) return;
    final proof = await identity.sign(
      dialerTranscript(
        dialerEphemeral: ownEphemeral,
        listenerEphemeral: peerEphemeral,
        dialerKey: ownKey,
        listenerKey: hello.identityKey,
      ),
    );
    _sendOuter(
      OuterFrame.auth(
        publicKeyB64: crypto.publicKeyBase64,
        signatureB64: base64.encode(proof),
      ),
    );
    await _finishPeerHello(hello);
  }

  // 리스너 쪽: 다이얼러는 커밋만 보냄. 내 임시키·서명을 먼저 보내고 auth의 공개를 기다림
  // 공개키/서명은 비밀이 아니라 상대 증명 전에 보내도 안전. identity/store 변경은 증명 성공 뒤로 미룸
  Future<void> _onDialerHello(
    HelloOuter hello,
    CryptoSession crypto,
    Uint8List ownKey,
  ) async {
    final commitment = hello.commitment;
    if (commitment == null ||
        hello.ephemeralKey != null ||
        hello.signature != null) {
      await _failPeerHello();
      return;
    }
    final peerKey = hello.identityKey;
    final ownEphemeral = crypto.publicKey;
    final signature = await identity.sign(
      listenerTranscript(
        dialerCommitment: commitment,
        listenerEphemeral: ownEphemeral,
        dialerKey: peerKey,
        listenerKey: ownKey,
      ),
    );
    _sendOuter(_helloFrame(crypto, ownKey, sig: base64.encode(signature)));
    _awaitingAuth = (auth) async {
      final revealed = auth.ephemeralKey;
      // 공개한 임시키가 커밋과 다르면 내 키를 본 뒤 키를 바꿔치기한 것 (SAS를 맞추려는 중간자)
      final opened = ephemeralCommitment(
        ephemeral: revealed,
        identityKey: peerKey,
      );
      final proven =
          constantTimeEquals(
            base64.encode(opened),
            base64.encode(commitment),
          ) &&
          await verifyAuth(
            transcript: dialerTranscript(
              dialerEphemeral: revealed,
              listenerEphemeral: ownEphemeral,
              dialerKey: peerKey,
              listenerKey: ownKey,
            ),
            signature: auth.signature,
            signerKey: peerKey,
          );
      if (!proven) {
        await _failPeerHello();
        return;
      }
      if (await _agree(crypto, revealed)) await _finishPeerHello(hello);
    };
  }

  // 키 합의. 깨진 키/all-zero shared secret/자기 공개키 반사는 거부
  // 워치독/오류로 이미 닫혔거나 동시 호출과 합류해 준비가 안 됐으면 false라 phase/onSecure/room join/store 변경을 건너뜀
  Future<bool> _agree(CryptoSession crypto, Uint8List peerEphemeral) async {
    try {
      await crypto.completeHandshake(base64.encode(peerEphemeral));
    } on Object {
      await _failPeerHello();
      return false;
    }
    return !_closed && crypto.isReady;
  }

  // 기대하지 않은 auth(리스너가 아니거나 hello 전이거나 이미 끝난 링크)는 프로토콜 위반: 다운그레이드/재생 시도로 보고 닫음
  Future<void> _onAuthOuter(AuthOuter auth) async {
    final pending = _awaitingAuth;
    if (_phase != _LinkPhase.handshaking || pending == null) {
      await _shutdown();
      return;
    }
    _awaitingAuth = null;
    await pending(auth);
  }
}
