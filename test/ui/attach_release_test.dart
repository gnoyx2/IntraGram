import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';

import '../support/fake_file_source_channel.dart';
import '_harness.dart';

// 네이티브 피커가 열려 있는 동안 채팅 화면이 닫혀도 뒤늦게 돌아온 pick
// 결과는 아무도 제안하지 않으니 그 소스의 native 권한을 바로 놓음
void main() {
  testWidgets('a pick that returns after the chat screen closed is released', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // 위젯 테스트의 invariant 검사는 tearDown보다 먼저 돌아서 finally에서 되돌려야 함
    try {
      await _run(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _run(WidgetTester tester) async {
  final fake = FakeFileSourceChannel()
    ..pickGate = Completer<void>()
    ..pickCount = 2
    ..install();
  final h = Harness();
  addTearDown(h.dispose);
  h.store.upsertConversation(conv('c1', secure: true, verified: true));
  await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
  await tester.pump();

  await tester.tap(find.byIcon(Icons.attach_file).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('File'));
  await tester.pump();
  expect(fake.count('pick'), 1, reason: 'the native picker is open');

  await tester.pumpWidget(const SizedBox()); // 피커가 열린 채 화면이 닫힘
  fake.pickGate!.complete();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(fake.count('release:s1'), 1);
  expect(fake.count('release:s2'), 1);
  expect(fake.count('open:'), 0, reason: 'nothing was offered or read');
}
