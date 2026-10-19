import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_input.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';

import '_harness.dart';

void main() {
  testWidgets('Enter while the IME is mid-composition does not send', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '한');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '한', composing: TextRange(start: 0, end: 1)),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      h.store.messages('c1'),
      isEmpty,
      reason: 'Enter must be left for the IME to finish composing',
    );
    expect(find.text('한'), findsOneWidget);
  });

  testWidgets('Enter sends normally once composition is committed', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '안녕');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: '안녕', composing: TextRange.empty),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    final msgs = h.store.messages('c1');
    expect(msgs, hasLength(1));
    expect(msgs.single.text, '안녕');
  });

  testWidgets('Shift+Enter inserts a newline instead of sending', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'line1');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(h.store.messages('c1'), isEmpty);
  });

  testWidgets(
    'typing signal refreshes every 2s while typing, then clears after 4s idle',
    (tester) async {
      final calls = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              enabled: true,
              onSend: (_) {},
              onAttach: () {},
              onTypingChanged: calls.add,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'h');
      await tester.pump();
      expect(calls, [true]);

      // 2초 경계에서 refresh (계속 입력해도 점이 사라지던 버그 방지). 4초는
      // refresh 주기(2초)의 배수라 idle로 꺼지기 바로 전에 refresh가 한 번 더
      // 끼어든 뒤 꺼짐: 의도된 동작(수신 쪽엔 마지막 갱신이라 무해함)
      await tester.pump(const Duration(seconds: 4, milliseconds: 100));
      expect(calls, [true, true, true, false]);
    },
  );
  testWidgets('a 320dp phone hides Attach while typing so the field is wider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    final attach = find.byTooltip('Send a file');
    expect(attach, findsOneWidget);
    final before = tester.getSize(find.byType(TextField)).width;

    await tester.enterText(find.byType(TextField), 'a long message');
    await tester.pump();
    expect(attach, findsNothing);
    expect(tester.getSize(find.byType(TextField)).width, greaterThan(before));

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(attach, findsOneWidget, reason: 'an empty field brings it back');
  });
}
