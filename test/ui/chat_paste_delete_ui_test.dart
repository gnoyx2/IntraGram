import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  testWidgets('composer sends clipboard text with one tap', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => <String, dynamic>{'value': true},
        'Clipboard.getData' => <String, dynamic>{'text': 'pasted memo'},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.content_paste), findsOneWidget);
    await tester.tap(find.byIcon(Icons.content_paste));
    await tester.pump();
    await tester.pump();

    final msgs = h.store.messages('c1');
    expect(msgs.single.text, 'pasted memo');
    expect(msgs.single.direction, MessageDirection.outgoing);
  });

  testWidgets('long-press a bubble deletes it for everyone', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(msg(id: 'm1', dir: MessageDirection.outgoing, text: 'oops'));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('oops'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete for everyone'), findsOneWidget);

    // 기본 테스트 뷰포트(800×600)에선 시트 하단 항목이 화면 밖으로 밀려 스크롤이 필요함
    await tester.ensureVisible(find.text('Delete for everyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for everyone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.store.messages('c1'), isEmpty);
  });
}
