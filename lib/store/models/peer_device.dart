part of '../models.dart';

@immutable
class PeerDevice {
  const PeerDevice({
    required this.peerId,
    required this.alias,
    required this.platform,
    required this.host,
    required this.port,
    required this.seenAt,
    this.hostsRoom = false,
    this.inRoom = false,
  });

  final String peerId;
  final String alias;
  final String platform;
  final String host;
  final int port;
  final DateTime seenAt;

  // 목록의 둘째 줄. 플랫폼을 안 밝힌 기기(mDNS os 속성 없음)는 영어 'Unknown' 대신 주소만
  String get detail => platform == 'Unknown' ? host : '$platform · $host';

  // mDNS TXT에 room=1이 있으면 true: 지금 그룹 방을 호스팅 중 (탭하면 합류)
  final bool hostsRoom;

  // mDNS TXT inRoom=1: 호스트든 멤버든 방 안. hostsRoom과 달리 탭해도 합류 안 됨
  final bool inRoom;

  PeerDevice copyWith({
    DateTime? seenAt,
    String? host,
    int? port,
    bool? hostsRoom,
    bool? inRoom,
  }) => PeerDevice(
    peerId: peerId,
    alias: alias,
    platform: platform,
    host: host ?? this.host,
    port: port ?? this.port,
    seenAt: seenAt ?? this.seenAt,
    hostsRoom: hostsRoom ?? this.hostsRoom,
    inRoom: inRoom ?? this.inRoom,
  );

  @override
  bool operator ==(Object other) =>
      other is PeerDevice &&
      other.peerId == peerId &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(peerId, host, port);
}
