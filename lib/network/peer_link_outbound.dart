part of 'peer_link.dart';

// 프레임이 나갈 때: send API, inner 프레임을 enc 봉투로(웹 게스트면 plain), 핸드셰이크 끝날 때까지 대기 큐.
// public인 건 레지스트리·전송 코드가 send*를 불러서
extension PeerLinkOutbound on PeerLink {
  // store에 먼저 쓰고 전선에 올림 (핸드셰이크 전이면 큐). inline·spillToFile 모드에서 너무 긴 글은 실패로 남음 (레지스트리가 이미 거르니 방어용)
  Future<void> sendText(
    String text, {
    required int ttlSeconds,
    String? replyToId,
  }) async {
    final tooLarge =
        store.largeMessageMode != LargeMessageMode.unlimited &&
        utf8.encode(text).length > kMaxInlineMessageBytes;
    final message = EphemeralMessage(
      id: newId(),
      conversationId: conversationId,
      direction: MessageDirection.outgoing,
      kind: MessageKind.text,
      senderAlias: identity.alias,
      createdAt: DateTime.now(),
      text: text,
      replyToId: replyToId,
      ttlSeconds: ttlSeconds,
      delivery: tooLarge ? DeliveryState.failed : DeliveryState.sending,
    );
    store.addMessage(message);
    if (tooLarge) return;
    await resendText(message);
  }

  // 저장된 내 글을 같은 id로 보냄. 재시도도 이 길이라 이미 받은 상대는 id로 걸러서 사본이 안 생김
  Future<void> resendText(EphemeralMessage message) async {
    Map<String, dynamic>? wire = InnerFrame.message(
      id: message.id,
      text: message.text ?? '',
      ttlSeconds: message.ttlSeconds,
      timestampMs: message.createdAt.millisecondsSinceEpoch,
      replyToId: message.replyToId,
    );
    if (store.conversation(conversationId)?.isRoom ?? false) {
      wire = await store.roomIntegrity.sign(conversationId, identity, wire);
    }
    if (wire == null ||
        _closed ||
        store.messageById(message.id)?.conversationId != conversationId) {
      return;
    }
    final ok = await sendRawInnerOrClose(wire);
    if (!ok) store.setDelivery(message.id, DeliveryState.failed);
  }

  Future<void> sendReaction(String messageId, String emoji, bool on) =>
      _sendInner(InnerFrame.react(id: messageId, emoji: emoji, on: on));

  // 호스트 -> 앱 멤버: 이 대화가 이제 방. peers는 방의 앱 피어 id 목록
  Future<void> sendRoomJoin(int count, {List<String>? peers}) =>
      _sendInner(InnerFrame.roomJoin(count: count, peers: peers));

  Future<void> sendReadReceipts(Iterable<String> messageIds) async {
    for (final id in messageIds) {
      await _sendInner(InnerFrame.read(id));
    }
  }

  Future<void> sendBurn(String messageId) =>
      _sendInner(InnerFrame.burn(messageId));

  Future<void> sendTyping({required bool active}) =>
      _sendInner(InnerFrame.typing(active: active));

  // inner 맵을 그대로 봉투에 담아 보냄 (게스트끼리 중계용이라 재조립 안 함)
  Future<bool> sendRawInner(Map<String, dynamic> inner) => _sendInner(inner);

  // sendRawInner인데 절대 안 던짐: 나갔으면 true, 못 나갔거나 봉인 오류면 false. 호출부가 결과를 보고 미전달 처리를 꼭 해야 함
  Future<bool> deliverRawInner(Map<String, dynamic> inner) async {
    try {
      return await _sendInner(inner);
    } on Object {
      return false;
    }
  }

  // 꼭 닿아야 하는 프레임용: 못 나가면 링크를 닫음. 그러면 종료 정리가 그 링크 경로를 지우고 전송을 실패로 돌려서 상대가 영영 안 기다림
  Future<bool> sendRawInnerOrClose(Map<String, dynamic> inner) async {
    final delivered = await deliverRawInner(inner);
    if (!delivered && !_closed) {
      try {
        await _shutdown();
      } on Object {
        // 종료가 실패해도 호출자에게 예외를 안 흘림
      }
    }
    return delivered;
  }

  // 실제 일은 _sendInnerSerial이 하고 여긴 _sendQueue에 줄만 세움: seq 배정 → seal → sink.add 순서가 안 섞여야 받는 쪽이 역행으로 안 버림.
  // 줄 서기 전에 개수·바이트를 잡아서 _pending과 합쳐 64개/1MiB 상한을 지킴
  Future<bool> _sendInner(Map<String, dynamic> inner) {
    final bytes = utf8.encode(jsonEncode(inner)).length;
    final byteCap = store.largeMessageMode == LargeMessageMode.unlimited
        ? kFrameCeilingBytes
        : kMaxPendingOutboundBytes;
    if (_pending.length + _inFlightFrames >= kMaxPendingOutboundFrames ||
        _pendingBytes + _inFlightBytes + bytes > byteCap) {
      return Future<bool>.value(false);
    }
    _inFlightFrames++;
    _inFlightBytes += bytes;
    final result = _sendQueue.then((_) => _sendInnerSerial(inner));
    // 하나가 던져도 큐는 계속 감 (원래 에러는 result로 호출부에 감)
    _sendQueue = result.then((_) {}, onError: (_) {});
    return result.whenComplete(() {
      _inFlightFrames--;
      _inFlightBytes -= bytes;
    });
  }

  Future<bool> _sendInnerSerial(Map<String, dynamic> inner) async {
    if (_closed) return false;
    final crypto = _crypto;
    if (crypto != null) {
      // 키 합의가 끝나도 상대 신원 증명이 끝나기(app 단계) 전엔 안 보냄: 증명 못 하는 상대가 프레임을 받게 됨. 큐에 뒀다가 증명 뒤 비움
      if (!crypto.isReady || _phase != _LinkPhase.app) {
        return _enqueuePending(inner);
      }
      if (_outSeq >= kMaxCryptoSequence) {
        // 카운터 소진 직전: nonce를 감느니 링크를 닫고 새 핸드셰이크
        await _shutdown();
        return false;
      }
      final seq = _outSeq++;
      final ({String nonce, String cipher, String mac}) parts;
      try {
        parts = await crypto.seal(inner, seq: seq);
      } on Object {
        // 봉인하다 링크가 닫혔으면 못 보낸 것뿐이라 false. 열린 채 던졌으면 이 번호는 이미 써서 상대는 빠진 프레임으로 봄: 닫고 던짐
        if (_closed) return false;
        await _shutdown();
        rethrow;
      }
      final written = _sendOuter(
        OuterFrame.enc(
          nonceB64: parts.nonce,
          cipherB64: parts.cipher,
          macB64: parts.mac,
          seq: seq,
        ),
      );
      _noteWrite(inner, written: written);
      return written;
    }
    if (transport == PeerTransport.web) {
      final written = _sendOuter(OuterFrame.plain(inner));
      _noteWrite(inner, written: written);
      return written;
    }
    // 암호는 정리됐는데 아직 안 닫힌 앱 링크
    return _enqueuePending(inner);
  }

  // 큐에 넣을 때가 아니라 소켓에 실제로 썼을 때만 sent로. 내가 이 대화에 보낸 글만 다룸 (중계하는 남의 메시지 제외).
  // 앱 링크로 쓴 건 ack 올 때까지 _unacked에 둠
  void _noteWrite(Map<String, dynamic> inner, {required bool written}) {
    final id = inner['id'];
    final m = inner['k'] == 'msg' && id is String
        ? store.messageById(id)
        : null;
    if (m == null || !m.isMine || m.conversationId != conversationId) return;
    if (written) {
      store.advanceDelivery(m.id, DeliveryState.sent);
      if (transport != PeerTransport.web) _unacked.add(m.id);
    } else if (m.delivery == DeliveryState.sending) {
      store.setDelivery(m.id, DeliveryState.failed);
    }
  }

  bool _sendOuter(String frame) {
    if (_closed) return false;
    try {
      channel.sink.add(frame);
      return true;
    } on Object {
      _shutdown();
      return false;
    }
  }

  // 핸드셰이크 끝날 때까지 담아 둠 (상한은 _sendInner가 이미 봄)
  bool _enqueuePending(Map<String, dynamic> inner) {
    _pending.add(inner);
    _pendingBytes += utf8.encode(jsonEncode(inner)).length;
    return true;
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    final queued = List<Map<String, dynamic>>.of(_pending);
    _pending.clear();
    _pendingBytes = 0;
    for (final inner in queued) {
      // 큐잉 때 true를 받은 호출자 대신 여기서 실패 처리 (링크 종료 + 내 메시지 failed)
      unawaited(
        sendRawInnerOrClose(inner).then((ok) {
          if (!ok) _noteWrite(inner, written: false);
        }),
      );
    }
  }
}
