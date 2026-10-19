import 'package:flutter/widgets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// provider 아님: initState에서 provider를 고치면 빌드 중 수정 에러남
// 읽는 쪽도 이벤트 시점에 한 번이라 반응성 불필요
// 한계: 방 위에 방을 쌓고 안쪽을 닫으면 null로 떨어짐 (다음 방 진입 전까지
// 스크린샷은 로컬 기록만)
String? foregroundConversationId;

// PIN 게이트가 떠 있으면 마지막 탭 하나만 쥐고 있다가 gateCleared에서 염
// 위젯 없이 테스트하려고 push는 콜백으로 주입
class ConversationOpener {
  ConversationOpener({required this.push, required this.gateUp});

  final void Function(String conversationId) push;

  final bool Function() gateUp;

  String? _pending;

  void open(String conversationId) {
    if (gateUp()) {
      _pending = conversationId;
      return;
    }
    push(conversationId);
  }

  void gateCleared() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    push(pending);
  }
}
