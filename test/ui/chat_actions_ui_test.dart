import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  testWidgets('long-press offers copy / reply / reactions', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'ping'));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.longPress(find.text('ping'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    // 남의 메시지는 내 쪽에서만 지울 수 있음
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsNothing);
    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);

    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    expect(
      h.store.messageById('m1')!.reactions.values.expand((s) => s),
      contains('👍'),
    );
    // 알약 리액션 칩이 이모지/개수를 따로 그림(붙은 문자열이 아니라 Row 두 조각)
    expect(find.text('👍'), findsOneWidget); // 버블 밑의 칩
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('reply from the sheet shows the compose strip', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'ping'));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.longPress(find.text('ping'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    // 입력창 위 인용 띠가 인용한 텍스트를 그대로 보여줌
    expect(find.text('ping'), findsNWidgets(2));
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
    'tapping the quoted reply strip jumps to and highlights the original',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      h.store
        ..upsertConversation(conv('c1', secure: true, verified: true))
        ..addMessage(
          msg(id: 'm1', dir: MessageDirection.incoming, text: 'original'),
        )
        ..addMessage(
          msg(
            id: 'm2',
            dir: MessageDirection.outgoing,
            text: 'reply text',
            replyToId: 'm1',
          ),
        );

      await tester.pumpWidget(
        h.wrap(const ChatRoomScreen(conversationId: 'c1')),
      );
      await tester.pump();
      await tester.pump();

      // m2의 버블은 m1의 텍스트를 보여주는 인용 띠를 갖고, m1 자신의 버블도 있음
      expect(find.text('original'), findsNWidgets(2));
      expect(find.text('reply text'), findsOneWidget);

      // 인용 띠가 m1 자신의 버블보다 먼저 만들어짐 (m2가 가장 최신이고 이 reversed ListView.builder는 index 0(최신)부터 그림)
      await tester.tap(find.text('original').first);
      await tester.pump();

      expect(find.byType(ColoredBox), findsWidgets);

      // 900ms 뒤 하이라이트가 꺼짐: 그 Future.delayed 타이머를 여기서 흘려
      // 보내야 함, 안 그러면 테스트 종료 뒤 pending timer로 assertion 남
      await tester.pump(const Duration(milliseconds: 900));
    },
  );

  testWidgets('chat room TTL menu sets the burn timer', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.timer_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Burn after 30s').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.store.conversation('c1')!.outgoingTtlSeconds, 30);
  });

  testWidgets('composer send writes an outgoing message to the store', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ping');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump();

    final msgs = h.store.messages('c1');
    expect(msgs, hasLength(1));
    expect(msgs.single.text, 'ping');
    expect(msgs.single.direction, MessageDirection.outgoing);
    expect(msgs.single.delivery, DeliveryState.failed); // 연결된 링크 없음
  });

  testWidgets('auto-accept files menu item is disabled until verified', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, sas: '314159'));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final item = tester.widget<PopupMenuItem<String>>(
      find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'auto',
      ),
    );
    expect(item.enabled, isFalse);
    expect(find.byIcon(Icons.done), findsNothing);
  });

  testWidgets('auto-accept files toggles on for a verified peer', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Auto-accept files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.store.conversation('c1')!.autoAcceptFiles, isTrue);
  });
}
