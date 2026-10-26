part of 'peer_link.dart';

// 암호 링크 성립 후의 선택적 승격: 핸드셰이크나 일반 채팅은 조직 자격을 요구하지 않음 (자격이 없는 이전 버전 앱과도 정상 대화함)
extension _PeerLinkOrg on PeerLink {
  void _startOrgAttestation() {
    if (_orgListening) return;
    _orgListening = true;
    store.orgCredentials.addListener(_orgChanged);
    _orgChanged();
  }

  void _orgChanged() => unawaited(_sendOrgCredential());

  Future<void> _sendOrgCredential() async {
    if (!isSecure ||
        _superseded ||
        _orgSending ||
        store.conversation(conversationId) == null) {
      return;
    }
    final book = store.orgCredentials;
    final credential = book.holderFor(identity);
    final binding = _crypto?.sessionBinding;
    final remote = remotePeerId;
    if (binding == null || remote == null) return;
    if (credential == null) {
      // 제시를 멈춤: 이 링크로 보낸 자격을 상대 화면에서도 내림 (옛 앱은 자격 없는 org_cred를 그냥 버림)
      if (_sentOrgDigest != null) {
        _sentOrgDigest = null;
        unawaited(sendRawInnerOrClose(<String, dynamic>{'k': 'org_cred'}));
      }
      return;
    }
    if (_sentOrgDigest == credential.digest) return;
    final generation = book.generation;
    _orgSending = true;
    try {
      final pop = await identity.sign(
        orgPopBytes(
          credentialDigest: credential.digest,
          policy: credential.policy,
          sessionBinding: binding,
          holderDialled: dialledByUs,
          holderPeerId: identity.peerId,
          verifierPeerId: remote,
        ),
      );
      if (!isSecure ||
          _superseded ||
          store.conversation(conversationId) == null ||
          generation != book.generation ||
          !identical(credential, book.holderFor(identity))) {
        return;
      }
      if (await sendRawInnerOrClose({
        'k': 'org_cred',
        'credential': credential.toWire(),
        'credentialDigest': credential.digest,
        'policy': credential.policy,
        'pop': base64.encode(pop),
      })) {
        _sentOrgDigest = credential.digest;
      }
    } on Object {
      // 키 교체(패닉)나 닫히는 링크가 일반 채팅 흐름을 막으면 안 돼서 실패는 버림
    } finally {
      _orgSending = false;
      // 서명하는 사이 자격을 바꿨거나 멈췄으면 지금 상태로 다시 보냄
      if (!identical(book.holderFor(identity), credential)) _orgChanged();
    }
  }

  // 검사는 한 번에 하나만 돌리고 그사이 온 건 마지막 것만 남김: 자격을 몇 번 바꿔 내도 끝에 낸 것이 보이고,
  // 프레임을 퍼부어도 서명 검사가 겹쳐 쌓이지 않음. 자격 없는 org_cred는 상대가 제시를 멈춘 상태임
  Future<void> _receiveOrgCredential(Map<String, dynamic> raw) async {
    final remote = remotePeerId;
    if (!isSecure ||
        _superseded ||
        remote == null ||
        store.conversation(conversationId) == null) {
      return;
    }
    _orgChecks++;
    if (raw['credential'] == null) {
      _orgPending = null;
      store.orgCredentials.forget(remote, owner: this);
      return;
    }
    _orgPending = raw;
    if (_orgVerifying) return;
    _orgVerifying = true;
    try {
      while (_orgPending != null) {
        final next = _orgPending!;
        _orgPending = null;
        await _checkOrgCredential(next, remote);
      }
    } finally {
      _orgVerifying = false;
    }
  }

  Future<void> _checkOrgCredential(
    Map<String, dynamic> raw,
    String remote,
  ) async {
    final credential = OrgCredential.fromWire(raw['credential']);
    final pop = wireBytes(raw['pop'], length: 64);
    final binding = _crypto?.sessionBinding;
    if (credential == null ||
        pop == null ||
        binding == null ||
        raw['credentialDigest'] != credential.digest ||
        raw['policy'] != credential.policy) {
      return;
    }
    final book = store.orgCredentials;
    if (book.alreadyChecked(remote, credential.digest, this)) return;
    // 검사 중에 새 org_cred(다른 자격·철회)가 오면 이 결과는 낡아서 안 남김
    final checkNo = _orgChecks;
    final generation = book.generation;
    final verifier = identity.peerId;
    final result = await verifyOrgPresentation(
      credential: credential,
      pop: pop,
      bundle: await book.trustBundle(),
      holderPeerId: remote,
      verifierPeerId: verifier,
      sessionBinding: binding,
      holderDialled: !dialledByUs,
    );
    if (!isSecure ||
        _superseded ||
        store.conversation(conversationId) == null ||
        generation != book.generation ||
        checkNo != _orgChecks ||
        verifier != identity.peerId) {
      return;
    }
    book.record(remote, result, owner: this);
  }

  void _stopOrgAttestation() {
    if (_orgListening) store.orgCredentials.removeListener(_orgChanged);
    _orgListening = false;
    _orgPending = null;
    final remote = remotePeerId;
    if (remote != null) store.orgCredentials.forget(remote, owner: this);
  }
}
