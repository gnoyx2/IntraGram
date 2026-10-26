part of 'peer_link.dart';

// 앱 피어 핸드셰이크 + 신원 증명 (v7, 커밋 후 공개):
// 1) 다이얼러 hello: 신원 키 + 임시키 커밋  2) 리스너 hello: 신원 키 + 임시키 + 서명(커밋·리스너 임시키·양쪽 신원 키)
// 3) 다이얼러 auth: 임시키 공개 + 서명(양쪽 임시키·신원 키). 리스너는 다이얼러 키를 모른 채 자기 키를 내고 다이얼러 키는 1)에서
// 묶여서 어느 쪽 중간자도 SAS 맞추는 키를 못 고름. 증명 전엔 상대 peerId·이름을 어디에도 안 씀
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

  // 증명 실패: 인바운드면 방금 생성한 임시 대화도 정리함 (다이얼한 대화는 사용자가 생성한 것이라 유지하고, 방 기록은 삭제하지 않음)
  Future<void> _failPeerHello([
    SystemEventKind reason = SystemEventKind.handshakeFailed,
  ]) {
    _failReason ??= reason;
    final inRoom = store.conversation(conversationId)?.isRoom ?? false;
    if (!dialledByUs && !inRoom) store.wipeConversation(conversationId);
    return _shutdown();
  }

  // 서명 전 구조 검사: peerId는 신원 키 해시여야 하고, 다이얼한 링크면 기대한 peerId여야 함 (DHCP 등으로 다른 기기가 해당 주소를 쓰면 연결하지 않음).
  // 자신의 peerId를 제시하는 hello나 작은 위수 키는 모두 거부함
  bool _acceptableHello(HelloOuter hello) =>
      hello.peerId != identity.peerId &&
      !isSmallOrderKey(hello.identityKey) &&
      peerIdOfKey(hello.identityKey) == hello.peerId &&
      (expectedPeerId == null || expectedPeerId == hello.peerId);

  Future<void> _onPeerHello(HelloOuter hello) async {
    final crypto = _crypto;
    final ownKey = identity.publicKey;
    // 기대한 peerId가 아니면 이 주소에 다른 기기가 있는 상태임
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

  // 리스너 쪽: 다이얼러는 커밋만 보냄. 내 임시키·서명을 먼저 보내고(비밀 아님) auth 공개를 기다림. 신원·store 변경은 증명 뒤로 미룸
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
      // 공개된 임시키가 커밋과 다르면 내 키를 확인한 뒤 바꿔치기한 중간자 공격으로 간주함 (SAS 일치 유도 방어)
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

  // 키 합의. 워치독·오류로 이미 닫혔거나 준비가 안 됐으면 false라 뒤 단계(phase, onSecure, 방 합류, store)를 건너뜀
  Future<bool> _agree(CryptoSession crypto, Uint8List peerEphemeral) async {
    try {
      await crypto.completeHandshake(base64.encode(peerEphemeral));
    } on Object {
      await _failPeerHello();
      return false;
    }
    return !_closed && crypto.isReady;
  }

  // 기대 안 한 auth(리스너가 아님, hello 전, 이미 끝난 링크)는 프로토콜 위반이라 닫음
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
