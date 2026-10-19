part of 'peer_link.dart';

// 프레임이 나갈 때 일어나는 모든 것: 타입 지정 send API, inner 프레임을
// enc 봉투로(웹 게스트면 plain) 봉인, raw sink write,
// 핸드셰이크 끝날 때까지 inner 프레임을 들고 있는 큐. public인 이유: 레지스트리와 transfer coordinator가
// 자기 라이브러리에서 PeerLink에 send*를 부르기 때문 (_ 헬퍼는 part 덕에 library-private)
extension PeerLinkOutbound on PeerLink {
  // 낙관적으로 스토어에 먼저 쓰고 그다음 전선에 올림 (핸드셰이크 전이면 큐잉). inline/spillToFile 모드에서
  // kMaxInlineMessageBytes보다 큰 텍스트는 실패로 기록되고 (link_registry가
  // 이미 스필/거부를 걸러서 여기 도달하는 건 방어용),
  // unlimited면 통과
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

  // 저장된 내 텍스트를 같은 id로 보냄. 재시도도 이 길이라 원본을 이미 받은 상대는 id로 걸러 사본이 안 생김
  Future<void> resendText(EphemeralMessage message) async {
    final ok = await sendRawInnerOrClose(
      InnerFrame.message(
        id: message.id,
        text: message.text ?? '',
        ttlSeconds: message.ttlSeconds,
        timestampMs: message.createdAt.millisecondsSinceEpoch,
        replyToId: message.replyToId,
      ),
    );
    if (!ok) store.setDelivery(message.id, DeliveryState.failed);
  }

  Future<void> sendReaction(String messageId, String emoji, bool on) =>
      _sendInner(InnerFrame.react(id: messageId, emoji: emoji, on: on));

  Future<bool> sendVerify() => _sendInner(InnerFrame.verify());

  // identity.peerId를 실어 보내서, 방에서 다른 멤버에게 그대로 중계돼도 받는 쪽이 누구 이름인지 알 수 있음
  Future<bool> sendRename(String alias) =>
      _sendInner(InnerFrame.rename(alias: alias, peerId: identity.peerId));

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

  // inner 맵을 그대로 봉투에 담아 보냄: 레지스트리가 포털 룸 게스트끼리 프레임을 중계할 때 씀
  // (이미 다른 게스트가 만든 프레임이라 재조립 안 함). 앱 링크면 enc, 웹 게스트면 plain
  Future<bool> sendRawInner(Map<String, dynamic> inner) => _sendInner(inner);

  // sendRawInner와 같되 절대 안 던짐: 나갔으면 true, 못 나갔거나
  // 열린 링크의 봉인 오류로 던졌으면 false (둘 다 똑같이 "미전달")
  // 처리 안 된 비동기 오류로 새지도 성공으로 기록되지도 않으니 호출부가 결과를 보고 미전달 경로(상대 통지, 링크 종료)를 꼭 타야 함
  Future<bool> deliverRawInner(Map<String, dynamic> inner) async {
    try {
      return await _sendInner(inner);
    } on Object {
      return false;
    }
  }

  // 상대에게 꼭 닿아야 하는 프레임용: deliverRawInner로 보내고
  // 못 나가면 이 링크를 닫음. 상대가 영영 못 받은 채 기다리는 대신
  // 링크 종료 정리(onClosed)가 그 링크의 경로를 지우고 전송을 실패로 돌림. 이미 닫히는 중이면 그 정리가 이미 돌고 있음
  Future<bool> sendRawInnerOrClose(Map<String, dynamic> inner) async {
    final delivered = await deliverRawInner(inner);
    if (!delivered && !_closed) {
      try {
        await _shutdown();
      } on Object {
        // 이미 실패한 전송의 결과는 false. 종료가 실패해도 호출자에게 예외를 안 흘림
      }
    }
    return delivered;
  }

  // 실제 작업은 _sendInnerSerial이 하고 여기선 _sendQueue에 이어붙이기만 함: seq 배정 -> seal
  // -> sink.add를 호출 순서 그대로 강제 (뒤섞이면 낮은 seq가 늦게 도착해 리시버가 "역행"으로 버려 메시지가 유실됨)
  // 큐에 붙이기 전에 바이트/개수를 예약해서 응답 없는 피어 상대로 무제한 쌓이지 않게 _pending과 합쳐
  // 64 frames/1MiB 상한을 적용 (_pending으로 빠지는 프레임은 그쪽이 이어받아 이중 집계 안
  // 됨)
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
    // 하나가 던져도 큐 자체는 안 끊기게 에러를 여기서 삼켜 다음 항목으로 이어짐 (원래 에러는 위 result로 호출부에 전파됨)
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
      // 키 합의가 끝나도 상대의 신원 증명이 통과해 app 단계가 되기
      // 전엔 안 보냄: 남의 peerId/공개키를 주장만 하고 증명 못
      // 하는 쪽이
      // 프레임을 받게 됨. 큐에 뒀다가 증명 뒤 flush
      if (!crypto.isReady || _phase != _LinkPhase.app) {
        return _enqueuePending(inner);
      }
      if (_outSeq >= kMaxCryptoSequence) {
        // 세션당 카운터 소진 직전: 같은 키로 nonce를 감아 재사용하느니 링크를 닫고 새 핸드셰이크를 강제함
        await _shutdown();
        return false;
      }
      final seq = _outSeq++;
      final ({String nonce, String cipher, String mac}) parts;
      try {
        parts = await crypto.seal(inner, seq: seq);
      } on Object {
        // 봉인하는 사이 링크가 닫혔으면(피어가 나가 세션이 파기됨) 못 보낸 것일 뿐이라 호출부는 false로 다룸
        // 링크가 열려 있는데 던졌으면 이 번호는 소모됐고 상대는 다음 번호를 빠진 프레임으로 봄: 닫고 올림
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
    // 크립토가 정리됐지만 아직 안 닫힌 앱 링크
    return _enqueuePending(inner);
  }

  // 대기 큐에 넣은 때가 아니라 소켓에 실제로 쓴 때만 sent로 올림
  // 내가 이 대화에 보낸 텍스트만 다룸 (방 호스트가 중계하는 남의 메시지는 안 건드림)
  // 앱 링크로 쓴 건 ack 올 때까지 _unacked에 둠 (웹 게스트는 ack를 안 보내서 제외)
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

  // 핸드셰이크 끝날 때까지 큐잉. 상한 검사는 _sendInner가 단일 입구에서 이미 했으니 여기선 옮겨 담기만 함
  // (_pending은 나중에 _flushPending이 다시 _sendInner로 흘려보내는 대기 칸)
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
      // 큐잉 때 이미 true를 받은 호출자 대신 여기서 실패를 처리함 (링크 종료 + 내 메시지 failed)
      unawaited(
        sendRawInnerOrClose(inner).then((ok) {
          if (!ok) _noteWrite(inner, written: false);
        }),
      );
    }
  }
}
