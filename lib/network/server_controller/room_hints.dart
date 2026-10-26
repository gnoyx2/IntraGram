import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/store/models.dart';
import '../discovery_engine.dart';

// mDNS room=1 조건: 내가 호스트(hostAlias == null)인 앱 그룹 방에 한 명 이상 붙어 있음 (웹 게스트 포털 방은 mDNS 피어가 합류하는 방이 아니라 제외)
bool hostsGroupRoom(Iterable<Conversation> conversations) => conversations.any(
  (c) =>
      c.isRoom &&
      c.transport == PeerTransport.app &&
      c.hostAlias == null &&
      c.online &&
      c.memberCount >= 2,
);

// 멤버도 포함하는 앱 그룹 방 inRoom=1 조건 (합류 유도가 아니라 정보, 웹 게스트 포털 방 제외)
bool inAnyGroupRoom(Iterable<Conversation> conversations) => conversations.any(
  (c) => c.isRoom && c.transport == PeerTransport.app && c.online,
);

// 대화 목록이 바뀔 때마다 mDNS 방 힌트를 한 번에 맞춤
final roomHintBridgeProvider = Provider<void>((ref) {
  ref.listen(conversationsProvider, (_, next) {
    final conversations = next.value ?? const [];
    unawaited(
      ref
          .read(discoveryControllerProvider.notifier)
          .setRoomHints(
            hostsRoom: hostsGroupRoom(conversations),
            inRoom: inAnyGroupRoom(conversations),
          ),
    );
  });
});
