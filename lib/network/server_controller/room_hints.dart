import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/store/models.dart';
import '../discovery_engine.dart';

// mDNS room=1 조건: 내가 호스트(hostAlias == null)고 한 명 이상 붙어 있음 (memberCount는 호스트 포함)
bool hostsGroupRoom(Iterable<Conversation> conversations) => conversations.any(
  (c) => c.isRoom && c.hostAlias == null && c.online && c.memberCount >= 2,
);

// 멤버도 포함하는 inRoom=1 조건 (합류 유도가 아니라 정보)
bool inAnyGroupRoom(Iterable<Conversation> conversations) =>
    conversations.any((c) => c.isRoom && c.online);

// 대화 목록이 바뀔 때마다 mDNS 방 힌트를 맞춤
final roomHintBridgeProvider = Provider<void>((ref) {
  ref.listen(conversationsProvider, (_, next) {
    final conversations = next.value ?? const [];
    final notifier = ref.read(discoveryControllerProvider.notifier);
    unawaited(notifier.setHostsRoom(hostsGroupRoom(conversations)));
    unawaited(notifier.setInRoom(inAnyGroupRoom(conversations)));
  });
});
