import 'package:flutter/material.dart';

import 'chat_room_screen.dart';

// 2단 배치가 떠 있을 때만 HomeScreen이 채움. 오른쪽 창에 띄웠으면 true
bool Function(String conversationId)? showChatInPane;

// 대화를 여는 길은 전부 여기로: 넓은 창이면 목록 옆 창에, 아니면 전체 화면으로 쌓음
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
