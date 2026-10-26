import 'package:flutter/material.dart';

import 'chat_room_screen.dart';

// HomeScreen이 소유한 대화 Navigator. 창 크기와 관계없이 같은 상태를 유지함
bool Function(String conversationId)? showChatInPane;

// 그 창에 열린 대화를 뒤로처럼 닫음 (Esc·⌘W가 초점 쪽에서 닫을 화면을 못 찾았을 때). 닫았으면 true
Future<bool> Function()? closePaneChat;

// HomeScreen이 없을 때만 독립 경로로 쌓음 (독립 화면·테스트에서도 사용 가능)
void openChat(BuildContext context, String conversationId) =>
    pushChat(Navigator.of(context), conversationId);

void pushChat(NavigatorState navigator, String conversationId) {
  if (showChatInPane?.call(conversationId) ?? false) return;
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ChatRoomScreen(conversationId: conversationId),
    ),
  );
}
