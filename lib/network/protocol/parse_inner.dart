part of '../protocol.dart';

// InboundInner.fromJson의 실제 파싱: 필수 필드는 _req*로 검증하고 없거나 형식/범위가 틀리면 _BadField로
// 프레임 전체를 거부 (?? ''/?? 0 기본값으로 정상 프레임인 척 안 만듦). 값이 있는 선택 필드가 틀려도 거부
// from/pid는 릴레이가 붙이는 표기라 신뢰 판단은 PeerLink의 인가 단계가 인증된 링크 신원으로 덮어써서 함
InboundInner _parseInner(Map<String, dynamic> j) {
  final from = _optText(j, 'from', 256);
  final pid = _optId(j, 'pid');
  switch (j['k']) {
    case 'msg':
      final text = j['text'];
      if (text is! String) throw const _BadField('text');
      return MessageInner(
        id: _reqId(j, 'id'),
        text: text,
        ttlSeconds: _optInt(j, 'ttl', 0, 1 << 31, 0),
        timestampMs: _optInt(j, 'ts', 0, 1 << 62, 0),
        replyToId: _optId(j, 're'),
        from: from,
        peerId: pid,
      );
    case 'ack':
      return AckInner(id: _reqId(j, 'id'));
    case 'read':
      return ReadInner(id: _reqId(j, 'id'), from: from, peerId: pid);
    case 'verify':
      return const VerifyInner();
    case 'rename':
      return RenameInner(
        alias: _reqText(j, 'alias', 256),
        peerId: _reqId(j, 'pid'),
      );
    case 'burn':
      return BurnInner(id: _reqId(j, 'id'));
    case 'screenshot':
      return ScreenshotInner(from: from);
    case 'typing':
      return TypingInner(active: _reqBool(j, 'on'), from: from);
    case 'react':
      return ReactInner(
        id: _reqId(j, 'id'),
        emoji: _reqText(j, 'emoji', 64),
        on: _reqBool(j, 'on'),
        from: from,
        peerId: pid,
      );
    case 'room_join':
      return RoomJoinInner(
        count: _reqInt(j, 'count', 0, 100000),
        peers: _optPeerIds(j),
      );
    case 'room_state':
      return RoomStateInner(
        count: _reqInt(j, 'count', 0, 100000),
        joined: _optText(j, 'joined', 256),
        left: _optText(j, 'left', 256),
        peers: _optPeerIds(j),
      );
    case 'file_offer':
      return _parseFileOffer(j, from: from, pid: pid);
    case 'file_accept':
      return FileAcceptInner(
        id: _reqId(j, 'id'),
        attempt: _reqId(j, 'at'),
        token: _reqId(j, 'tok'),
        from: from,
        peerId: pid,
      );
    case 'file_reject':
      return FileRejectInner(
        id: _reqId(j, 'id'),
        attempt: _reqId(j, 'at'),
        from: from,
        peerId: pid,
      );
    case 'file_cancel':
      return FileCancelInner(
        id: _reqId(j, 'id'),
        attempt: _reqId(j, 'at'),
        from: from,
        peerId: pid,
      );
    case 'file_received':
      return FileReceivedInner(
        id: _reqId(j, 'id'),
        attempt: _reqId(j, 'at'),
        from: from,
        peerId: pid,
      );
    case 'file_retry':
      return FileRetryInner(
        id: _reqId(j, 'id'),
        attempt: _reqId(j, 'at'),
        from: from,
        peerId: pid,
      );
    case 'file_unavailable':
      return FileUnavailableInner(
        id: _reqId(j, 'id'),
        attempt: _reqId(j, 'at'),
        target: _reqId(j, 'to'),
      );
    default:
      final kind = j['k']?.toString() ?? '?';
      return UnknownInner(
        kind: kind.length > 64 ? kind.substring(0, 64) : kind,
      );
  }
}

// file_offer 전용 조합 검증: pull은 토큰 + 사설 RFC1918
// IPv4 endpoint 셋 다 필수, push는 셋 다 없어야 함
InboundInner _parseFileOffer(
  Map<String, dynamic> j, {
  required String? from,
  required String? pid,
}) {
  final mode = j['md'];
  if (mode != 'push' && mode != 'pull') throw const _BadField('md');
  final token = _optId(j, 'tok');
  final srcHost = _optText(j, 'sh', 64);
  final srcPort = _optIntOrNull(j, 'sp', 1, 65535);
  if (mode == 'pull') {
    if (token == null) throw const _BadField('tok');
    if (srcHost == null ||
        srcPort == null ||
        NetworkGuard.parsePeerEndpoint(srcHost, srcPort) == null) {
      throw const _BadField('sh');
    }
  } else if (token != null || srcHost != null || srcPort != null) {
    throw const _BadField('tok');
  }
  final mime = _optText(j, 'mime', 255);
  final voice = _optBool(j, 'vc');
  final digest = j['dg'];
  if (digest != null && wireBytes(digest, length: 32) == null) {
    throw const _BadField('dg');
  }
  return FileOfferInner(
    id: _reqId(j, 'id'),
    attempt: _reqId(j, 'at'),
    mode: mode as String,
    name: _reqText(j, 'name', 1024),
    size: _reqInt(j, 'size', 0, 1 << 62),
    // 음성 MIME은 피어가 조작할 수 있으니 저장 전부터 실제 인코더 형식으로 고정함
    mime: voice ? 'audio/wav' : mime,
    srcHost: srcHost,
    srcPort: srcPort,
    thumb: _optText(j, 'th', (kMaxThumbBytes + 2) ~/ 3 * 4),
    preview: _optText(j, 'pv', kSpillPreviewBytes * 4),
    voice: voice,
    enc: _optBool(j, 'ec'),
    batchId: _optId(j, 'bid'),
    ttlSeconds: _optInt(j, 'ttl', 0, 1 << 31, 0),
    token: token,
    from: from,
    peerId: pid,
    to: _optId(j, 'to'),
    digest: digest as String?,
  );
}

List<String> _optPeerIds(Map<String, dynamic> j) {
  final raw = j['peers'];
  if (raw == null) return const [];
  if (raw is! List || raw.length > 256) throw const _BadField('peers');
  final ids = <String>[];
  for (final value in raw) {
    final id = wireId(value);
    if (id == null || ids.contains(id)) throw const _BadField('peers');
    ids.add(id);
  }
  return ids;
}
