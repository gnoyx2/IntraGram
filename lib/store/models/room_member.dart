part of '../models.dart';

// 방은 멤버 링크 여럿이 대화 하나를 나눠 써서 Conversation의 sas·확인 필드 하나로는 멤버별 세션을 구분 못 함.
// 그래서 멤버마다 따로 둠 (1:1은 안 씀)
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

  // 링크가 살아 있으면 true. 끊기면 goOffline으로 SAS·확인도 지우고 다시 들어오면 새 세션 값으로 채움
  final bool online;

  // 멤버 목록 아이콘용 플랫폼 (방의 Conversation.peerPlatform은 'Room'이라 못 씀)
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

  // copyWith로는 sas를 null로 못 돌려서 새로 만듦 (이름·플랫폼은 남겨서 다시 들어와도 이름이 보임)
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
