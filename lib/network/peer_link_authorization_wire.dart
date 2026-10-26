part of 'peer_link.dart';

// kind별로 wire에 실을 수 있는 키. 정규화 맵은 이 키만 복사해서 끼워 넣은 여분 키는 안 넘어감
const Map<String, Set<String>> _kInnerWireKeys = <String, Set<String>>{
  'msg': {'id', 'text', 'ttl', 'ts', 're', ...roomAuthorKeys},
  'ack': {'id'},
  'read': {'id'},
  'verify': <String>{},
  'rename': {'alias'},
  'burn': {'id'},
  'screenshot': <String>{},
  'typing': {'on'},
  'react': {'id', 'emoji', 'on'},
  'org_cred': {'credential', 'credentialDigest', 'policy', 'pop'},
  'room_join': {'count', 'peers', ..._checkpointKeys},
  'room_state': {'count', 'joined', 'left', 'peers', ..._checkpointKeys},
  'file_offer': {
    'id', 'at', 'md', 'name', 'size', 'mime', 'sh', 'sp', //
    'th', 'pv', 'bid', 'ttl', 'tok', 'vc', 'ec', 'to', 'dg', 'sk',
  },
  'file_accept': {'id', 'at', 'tok'},
  'file_reject': {'id', 'at'},
  'file_cancel': {'id', 'at'},
  'file_received': {'id', 'at', 'rc'},
  'file_retry': {'id', 'at'},
  'file_unavailable': {'id', 'at', 'to'},
};

const _checkpointKeys = {'roomIntegrityId', 'checkpointNo', 'merkleRoot'};

// 중첩 객체 키는 통째로 복사하지 않고 아는 필드만 다시 씀 (형식이 틀리면 그 키만 버리고 나머지 프레임은 그대로 감)
const Map<String, Map<String, dynamic>? Function(Object?)> _kNestedWire = {
  'rc': canonicalAttestationWire,
  'credential': canonicalCredentialWire,
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

extension _PeerLinkAuthorizationWire on PeerLink {
  // kind별 허용 키만 복사하고(null 제외) 발신자 kind면 from/pid를 인증된 값으로 도장 찍음. raw를 통째로 안 펼침
  Map<String, dynamic> _canonicalWire(Map<String, dynamic> raw) {
    final kind = raw['k'] as String;
    final allowed = _kInnerWireKeys[kind] ?? const <String>{};
    final wire = <String, dynamic>{
      'k': kind,
      for (final key in allowed) key: ?_wireValue(key, raw[key]),
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

const _kCryptoWireBytes = {
  'pop': 64,
  'authorPubKey': 32,
  'prevAuthorHash': 32,
  'payloadCommitment': 32,
  'payloadSalt': 32,
  'authorSig': 64,
  'merkleRoot': 32,
};

Object? _wireValue(String key, Object? value) {
  if (value == null) return null;
  final length = _kCryptoWireBytes[key];
  if (length != null &&
      (value is! String || value.length > (length + 2) ~/ 3 * 4)) {
    // 잘못된 서명 필드 표식은 남겨서 구형 무서명 메시지로 다운그레이드되지 않게 함.
    return '';
  }
  final nested = _kNestedWire[key];
  return nested == null ? value : nested(value);
}
