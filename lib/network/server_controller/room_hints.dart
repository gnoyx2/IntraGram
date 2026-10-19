import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/store/models.dart';
import '../discovery_engine.dart';

// hostAlias == null이면 이 기기가 호스트, memberCount >=
// 2면 최소 한 명이 붙어 있음 (호스트 포함 인원) mDNS room=1 조건
bool hostsGroupRoom(Iterable<Conversation> conversations) => conversations.any(
  (c) => c.isRoom && c.hostAlias == null && c.online && c.memberCount >= 2,
);

// hostsGroupRoom과 달리 멤버도 포함 (hostAlias != null). "탭하면 합류"를 뜻하지 않는 정보성 mDNS 힌트용
bool inAnyGroupRoom(Iterable<Conversation> conversations) =>
    conversations.any((c) => c.isRoom && c.online);

// 방을 호스팅하는 동안 mDNS 광고에 room=1 힌트를 켜서 다른 기기 목록에 "hosting a room" 칩이 뜨게 함
// 멤버로 들어가 있는 동안엔 inRoom=1만 켜서 "방 참여 중" 표시 (합류 유도 아님)
final roomHintBridgeProvider = Provider<void>((ref) {
  ref.listen(conversationsProvider, (_, next) {
    final conversations = next.value ?? const [];
    final notifier = ref.read(discoveryControllerProvider.notifier);
    unawaited(notifier.setHostsRoom(hostsGroupRoom(conversations)));
    unawaited(notifier.setInRoom(inAnyGroupRoom(conversations)));
  });
});
