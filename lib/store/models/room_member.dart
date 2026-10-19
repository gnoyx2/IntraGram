part of '../models.dart';

// 방은 호스트 쪽에서 멤버 링크 여러 개가 대화 하나(Conversation.id)를 공유해서, Conversation의 단일
// sas/localVerified/peerVerified로는 멤버마다 다른 암호 세션을 구분 못 함 (세 번째가 들어오면 필드가 덮임)
// 그래서 멤버별로 따로 들고 있고, 1:1 대화는 안 씀
@immutable
class RoomMember {
  const RoomMember({
    required this.alias,
    this.platform = 'Unknown',
    this.sas,
    this.localVerified = false,
    this.peerVerified = false,
    this.online = true,
  });

  final String alias;

  // 이 멤버로 가는 링크가 살아있으면 true. 끊기면 goOffline으로 false + SAS/검증 초기화,
  // 재합류하면 새 세션 값으로 다시 채워짐
  final bool online;

  // hello로 받은 상대 플랫폼 라벨. 멤버 목록의 기기별 아이콘용
  // (Conversation.peerPlatform은 방이면 'Room' 고정이라 못 씀)
  final String platform;
  final String? sas;
  final bool localVerified;
  final bool peerVerified;

  bool get verified => localVerified && peerVerified;

  RoomMember copyWith({
    String? alias,
    String? platform,
    String? sas,
    bool? localVerified,
    bool? peerVerified,
    bool? online,
  }) => RoomMember(
    alias: alias ?? this.alias,
    platform: platform ?? this.platform,
    sas: sas ?? this.sas,
    localVerified: localVerified ?? this.localVerified,
    peerVerified: peerVerified ?? this.peerVerified,
    online: online ?? this.online,
  );

  // copyWith는 ?? 폴백이라 sas를 null로 못 되돌려서, SAS/검증을 지우려면 새 인스턴스를 씀
  // alias/platform은 유지 (재합류 UI가 이름을 계속 보여줌)
  RoomMember goOffline() =>
      RoomMember(alias: alias, platform: platform, online: false);

  @override
  bool operator ==(Object other) =>
      other is RoomMember &&
      other.alias == alias &&
      other.platform == platform &&
      other.sas == sas &&
      other.localVerified == localVerified &&
      other.peerVerified == peerVerified &&
      other.online == online;

  @override
  int get hashCode =>
      Object.hash(alias, platform, sas, localVerified, peerVerified, online);
}
