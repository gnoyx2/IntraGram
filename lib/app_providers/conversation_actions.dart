import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/network/server_controller.dart';

// 대화 종료 공통 처리 (채팅 화면 메뉴, 홈 길게 누르기). 링크를 닫고 RAM 기록을 지움.
// 내가 연 게스트 방이면 포털도 꺼서(토큰 폐기) 브라우저가 같은 주소로 바로 다시 못 들어옴
Future<void> endConversation(WidgetRef ref, String conversationId) async {
  final registry = ref.read(linkRegistryProvider);
  if (registry.portalRoomId == conversationId) {
    await ref.read(serverControllerProvider.notifier).setPortalEnabled(false);
  }
  await registry.disconnect(conversationId);
  ref.read(inMemoryStoreProvider).wipeConversation(conversationId);
}
