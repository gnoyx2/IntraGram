part of '../models.dart';

@immutable
class EphemeralMessage {
  const EphemeralMessage({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.kind,
    required this.senderAlias,
    this.senderPeerId,
    required this.createdAt,
    this.text,
    this.transferId,
    this.replyToId,
    this.reactions = const <String, Set<String>>{},
    this.ttlSeconds = 0,
    this.burnAt,
    required this.delivery,
    this.burned = false,
    this.systemEvent,
    this.readBy = const <String>{},
  });

  final String id;
  final String conversationId;
  final MessageDirection direction;
  final MessageKind kind;
  final String senderAlias;

  // _PeerLinkAuthorization이 확정한 보낸 사람 peerId (웹 게스트는 peerId가 없어서 alias). reactions·readBy 키도 이 기준.
  // 내가 만든 메시지(보낸 것, 시스템 줄)는 null
  final String? senderPeerId;
  final DateTime createdAt;

  final String? text;

  // 그릴 때 번역함. RAM 전용이라 직렬화·동등성 비교에 안 들어감 (시스템 메시지는 vault에 안 담김)
  final SystemEvent? systemEvent;

  final String? transferId;

  // 원본이 소각·삭제되면 UI가 삭제된 메시지로 보여 줌 (소각된 글의 사본을 안 남김)
  final String? replyToId;

  // 반응한 사람 peerId(웹 게스트는 alias) -> 그 사람이 건 이모지 집합 (한 사람이 여러 개 가능)
  final Map<String, Set<String>> reactions;

  final int ttlSeconds;

  // 소각 예정 벽시계 시각. 카운트다운이 실제로 시작될 때(읽었을 때) 채워지고 그전엔 null
  final DateTime? burnAt;

  final DeliveryState delivery;
  final bool burned;

  // 방에서 읽음이 확인된 멤버 peerId(웹 게스트는 alias) 집합. 1:1은 delivery의 read로 충분해서 빈 집합
  final Set<String> readBy;

  bool get hasTimer => ttlSeconds > 0;
  bool get isMine => direction == MessageDirection.outgoing;

  EphemeralMessage copyWith({
    String? senderAlias,
    String? text,
    Map<String, Set<String>>? reactions,
    int? ttlSeconds,
    DateTime? burnAt,
    DeliveryState? delivery,
    bool? burned,
    Set<String>? readBy,
  }) {
    return EphemeralMessage(
      id: id,
      conversationId: conversationId,
      direction: direction,
      kind: kind,
      senderAlias: senderAlias ?? this.senderAlias,
      senderPeerId: senderPeerId,
      createdAt: createdAt,
      text: text ?? this.text,
      transferId: transferId,
      replyToId: replyToId,
      reactions: reactions ?? this.reactions,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      burnAt: burnAt ?? this.burnAt,
      delivery: delivery ?? this.delivery,
      burned: burned ?? this.burned,
      systemEvent: systemEvent,
      readBy: readBy ?? this.readBy,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'conversationId': conversationId,
    'direction': direction.name,
    'kind': kind.name,
    'senderAlias': senderAlias,
    if (senderPeerId != null) 'senderPeerId': senderPeerId,
    // 시각은 UTC로 저장: 저장과 복원 사이에 시간대가 바뀌어도 남은 소각 시간이 그대로임
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (text != null) 'text': text,
    if (transferId != null) 'transferId': transferId,
    if (replyToId != null) 'replyToId': replyToId,
    if (reactions.isNotEmpty)
      'reactions': reactions.map((k, v) => MapEntry(k, v.toList())),
    'ttlSeconds': ttlSeconds,
    if (burnAt case final at?) 'burnAt': at.toUtc().toIso8601String(),
    'delivery': delivery.name,
    'burned': burned,
    if (readBy.isNotEmpty) 'readBy': readBy.toList(),
  };

  factory EphemeralMessage.fromJson(Map<String, dynamic> j) => EphemeralMessage(
    id: (j['id'] ?? '').toString(),
    conversationId: (j['conversationId'] ?? '').toString(),
    direction: _enumByName(
      MessageDirection.values,
      j['direction'],
      MessageDirection.incoming,
    ),
    kind: _enumByName(MessageKind.values, j['kind'], MessageKind.text),
    senderAlias: (j['senderAlias'] ?? 'peer').toString(),
    senderPeerId: j['senderPeerId']?.toString(),
    createdAt:
        DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
    text: j['text']?.toString(),
    transferId: j['transferId']?.toString(),
    replyToId: j['replyToId']?.toString(),
    // 구버전 vault는 alias -> emoji 문자열 하나였음. 리스트가 아니면 한 개짜리 집합으로 읽어 옛 아카이브도 열리게 함
    reactions:
        (j['reactions'] as Map?)?.map(
          (k, v) => MapEntry(
            k.toString(),
            v is List ? v.map((e) => e.toString()).toSet() : {v.toString()},
          ),
        ) ??
        const <String, Set<String>>{},
    ttlSeconds: (j['ttlSeconds'] as num?)?.toInt() ?? 0,
    burnAt: _readBurnAt(j['burnAt']),
    delivery: _enumByName(
      DeliveryState.values,
      j['delivery'],
      DeliveryState.sent,
    ),
    burned: j['burned'] == true,
    readBy:
        (j['readBy'] as List?)?.map((e) => e.toString()).toSet() ??
        const <String>{},
  );

  @override
  bool operator ==(Object other) =>
      other is EphemeralMessage &&
      other.id == id &&
      other.burned == burned &&
      other.delivery == delivery &&
      other.burnAt == burnAt &&
      other.text == text &&
      _mapEq.equals(other.reactions, reactions) &&
      _setEq.equals(other.readBy, readBy);

  @override
  int get hashCode => Object.hash(
    id,
    burned,
    delivery,
    burnAt,
    text,
    _mapEq.hash(reactions),
    _setEq.hash(readBy),
  );
}

// 오프셋 없는 옛 형식은 어느 시간대에서 저장했는지 몰라 몇 시간 늦게 소각될 수 있음: 이미 지난 것으로 봄
DateTime? _readBurnAt(Object? raw) {
  if (raw == null) return null;
  final at = DateTime.tryParse('$raw');
  if (at == null) return null;
  return at.isUtc ? at.toLocal() : DateTime.fromMillisecondsSinceEpoch(0);
}
