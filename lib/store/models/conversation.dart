part of '../models.dart';

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.peerAlias,
    required this.peerPlatform,
    required this.transport,
    required this.startedAt,
    this.peerHost,
    this.peerPort,
    this.peerId,
    this.online = true,
    this.secure = false,
    this.outgoingTtlSeconds = 0,
    this.peerTyping = false,
    this.unread = 0,
    this.sas,
    this.localVerified = false,
    this.peerVerified = false,
    this.autoAcceptFiles = false,
    this.isRoom = false,
    this.memberCount = 0,
    this.hostAlias,
    this.hostPeerId,
    this.roomRecipientIds = const <String>[],
    this.members = const <String, RoomMember>{},
    this.vaultOptOut = false,
    this.blocked = false,
  });

  final String id;
  final String peerAlias;
  final String peerPlatform;
  final PeerTransport transport;
  final DateTime startedAt;
  final String? peerHost;
  final int? peerPort;

  // 상대의 안정적인 기기 식별자(hello의 peerId). 방이면 늘 null (멤버별 값은 RoomMember가 가짐).
  // 탐지된 피어로 다이얼한 대화는 광고된 값을 기대값으로 들고 시작하고(증명은 링크가 함), 수동 IP·인바운드 대화는 핸드셰이크가 증명한 값으로 채움.
  // 재연결·인바운드 중복 합치기가 그 IP의 상대가 진짜 같은 피어인지 볼 때 씀 (IP는 DHCP로 바뀔 수 있음)
  final String? peerId;

  // 이번 실행 동안 차단한 상대 (LinkRegistry.blockPeer). 신원 키가 실행마다 바뀌어서 저장하지 않음
  final bool blocked;

  final bool online;

  // X25519·ChaCha20 세션 키가 서면 true. 웹 게스트는 늘 false (LAN 구간이 브라우저 평문)
  final bool secure;

  final int outgoingTtlSeconds;
  final bool peerTyping;
  final int unread;

  // 공유 키에서 유도한 6자리 SAS (양쪽 동일). 핸드셰이크 전엔 null
  final String? sas;

  final bool localVerified;

  final bool peerVerified;

  // 양쪽 다 SAS 일치를 확인해야 true: 능동적 중간자를 막는 유일한 수단.
  // 한쪽만 눌렀으면 localVerified만 켜져 UI가 대기 중으로 보임 (한쪽이 공격자면 영원히 대기 중에 갇힘)
  bool get verified => localVerified && peerVerified;

  // true면 들어온 file_offer를 묻지 않고 수락함. 검증된 1:1에서만 켜짐 (방은 늘 물어봄). RAM 전용
  final bool autoAcceptFiles;

  // 호스트 중계 그룹 방. 고정 호스트 신원이 없어서 보관해도 되살릴 수 없으니 vault에 안 담김
  final bool isRoom;

  // 호스트 쪽에서만 유지됨 (호스트 포함 인원). 멤버 쪽은 0
  final int memberCount;

  // 내가 멤버로 들어간 방의 호스트 alias (내가 호스트면 null). 있으면 UI가 메시지가 호스트 기기를 거친다고 알림
  final String? hostAlias;

  // 내가 멤버로 들어간 방의 확정된 호스트 peerId: 처음 정당한 room_join을 인가한 링크 상대의 인증된 신원.
  // 그 뒤 room_join·room_state는 이 peerId의 링크에서만 받음 (alias는 표시용이라 권한 판단에 안 씀). 호스트면 null, RAM 전용
  final String? hostPeerId;

  // 인증된 방 호스트가 알려 준 지금 앱 피어 ID들. 받는 사람별 파일 토큰 라우팅에 씀. RAM 전용
  final List<String> roomRecipientIds;

  // 방 멤버별 SAS 검증 상태 (key = 멤버 peerId). 1:1은 비어 있고 위의 sas·localVerified·peerVerified를 씀
  final Map<String, RoomMember> members;

  // 나가면서 저장 안 함을 고르면 true. toSnapshot이 이 대화와 메시지·전송을 vault에서 통째로 뺌. RAM 전용
  final bool vaultOptOut;

  Conversation copyWith({
    String? peerAlias,
    String? peerPlatform,
    int? peerPort,
    String? peerId,
    bool? online,
    bool? secure,
    int? outgoingTtlSeconds,
    bool? peerTyping,
    int? unread,
    String? sas,
    bool? localVerified,
    bool? peerVerified,
    bool? autoAcceptFiles,
    bool? isRoom,
    int? memberCount,
    String? hostAlias,
    String? hostPeerId,
    List<String>? roomRecipientIds,
    Map<String, RoomMember>? members,
    bool? vaultOptOut,
    bool? blocked,
  }) {
    return Conversation(
      id: id,
      peerAlias: peerAlias ?? this.peerAlias,
      peerPlatform: peerPlatform ?? this.peerPlatform,
      transport: transport,
      startedAt: startedAt,
      peerHost: peerHost,
      peerPort: peerPort ?? this.peerPort,
      peerId: peerId ?? this.peerId,
      online: online ?? this.online,
      secure: secure ?? this.secure,
      outgoingTtlSeconds: outgoingTtlSeconds ?? this.outgoingTtlSeconds,
      peerTyping: peerTyping ?? this.peerTyping,
      unread: unread ?? this.unread,
      sas: sas ?? this.sas,
      localVerified: localVerified ?? this.localVerified,
      peerVerified: peerVerified ?? this.peerVerified,
      autoAcceptFiles: autoAcceptFiles ?? this.autoAcceptFiles,
      isRoom: isRoom ?? this.isRoom,
      memberCount: memberCount ?? this.memberCount,
      hostAlias: hostAlias ?? this.hostAlias,
      hostPeerId: hostPeerId ?? this.hostPeerId,
      roomRecipientIds: roomRecipientIds ?? this.roomRecipientIds,
      members: members ?? this.members,
      vaultOptOut: vaultOptOut ?? this.vaultOptOut,
      blocked: blocked ?? this.blocked,
    );
  }

  // 되살린 대화는 라이브 링크가 아니라 기록: fromJson이 online·secure·verified·sas·typing을 초기값으로 되돌림.
  // 신원 키가 실행마다 바뀌어서 같은 상대가 다시 붙어도 새 대화가 열림
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'peerAlias': peerAlias,
    'peerPlatform': peerPlatform,
    'transport': transport.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'outgoingTtlSeconds': outgoingTtlSeconds,
  };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: (j['id'] ?? '').toString(),
    peerAlias: (j['peerAlias'] ?? 'peer').toString(),
    peerPlatform: (j['peerPlatform'] ?? 'Unknown').toString(),
    transport: _enumByName(
      PeerTransport.values,
      j['transport'],
      PeerTransport.app,
    ),
    startedAt:
        DateTime.tryParse('${j['startedAt']}')?.toLocal() ?? DateTime.now(),
    outgoingTtlSeconds: (j['outgoingTtlSeconds'] as num?)?.toInt() ?? 0,
    online: false,
    secure: false,
  );

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      other.id == id &&
      other.peerAlias == peerAlias &&
      other.peerId == peerId &&
      other.online == online &&
      other.secure == secure &&
      other.outgoingTtlSeconds == outgoingTtlSeconds &&
      other.peerTyping == peerTyping &&
      other.unread == unread &&
      other.sas == sas &&
      other.localVerified == localVerified &&
      other.peerVerified == peerVerified &&
      other.autoAcceptFiles == autoAcceptFiles &&
      other.isRoom == isRoom &&
      other.memberCount == memberCount &&
      other.hostAlias == hostAlias &&
      other.hostPeerId == hostPeerId &&
      const ListEquality<String>().equals(
        other.roomRecipientIds,
        roomRecipientIds,
      ) &&
      _roomMembersEq.equals(other.members, members) &&
      other.vaultOptOut == vaultOptOut &&
      other.blocked == blocked;

  @override
  int get hashCode => Object.hash(
    id,
    peerAlias,
    peerId,
    online,
    secure,
    outgoingTtlSeconds,
    peerTyping,
    unread,
    sas,
    localVerified,
    peerVerified,
    autoAcceptFiles,
    isRoom,
    memberCount,
    hostAlias,
    hostPeerId,
    const ListEquality<String>().hash(roomRecipientIds),
    _roomMembersEq.hash(members),
    vaultOptOut,
    blocked,
  );
}
