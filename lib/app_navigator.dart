import 'package:flutter/widgets.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// provider가 아님: initState에서 provider를 고치면 빌드 중 수정 오류가 남. 방 위에 방을 쌓고 안쪽을 닫으면 null로 떨어짐
// (다음 대화를 열 때까지 스크린샷은 내 기록만)
String? foregroundConversationId;

// PIN 게이트가 떠 있으면 마지막 탭 하나만 쥐었다가 gateCleared에서 엶 (push는 위젯 없이 테스트하려고 주입)
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
