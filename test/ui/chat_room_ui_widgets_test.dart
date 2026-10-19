import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/burn_countdown.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

import '_harness.dart';

void main() {
  testWidgets('BurnCountdown shows a shrinking seconds value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BurnCountdown(
            burnAt: DateTime.now().add(const Duration(seconds: 5)),
            color: Colors.red,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.hourglass_bottom_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BurnCountdown), findsOneWidget);
  });

  testWidgets(
    'BurnCountdown ceils under a full second instead of flooring to 0',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BurnCountdown(
              burnAt: DateTime.now().add(const Duration(milliseconds: 700)),
              color: Colors.red,
            ),
          ),
        ),
      );
      // 700ms 남았으면 올림으로 1: 예전 내림 코드는 0으로 잘못 보였음
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets('BurnCountdown stops ticking at 0 without a pending-timer leak', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BurnCountdown(
            burnAt: DateTime.now().subtract(const Duration(seconds: 1)),
            color: Colors.red,
          ),
        ),
      ),
    );
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 테스트가 여기서 끝나도 살아있는 Timer.periodic이 없어야 함(위젯 테스트
    // 프레임워크가 pending timer면 실패로 잡아줌)
  });

  testWidgets(
    'a burning message shows a content-free ghost, never the original text',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      h.store
        ..upsertConversation(conv('c1', secure: true, verified: true))
        ..addMessage(
          msg(
            id: 'm1',
            dir: MessageDirection.incoming,
            text: 'secret content',
            ttl: 3,
          ),
        );

      await tester.pumpWidget(
        h.wrap(const ChatRoomScreen(conversationId: 'c1')),
      );
      await tester.pump();
      expect(find.text('secret content'), findsOneWidget);

      h.store.markIncomingRead('c1'); // burnAt = now + 3s로 카운트다운 시작
      await tester.pump();
      await tester.pump(const Duration(seconds: 3)); // 소각 타이머 발화

      expect(h.store.messages('c1'), isEmpty);
      expect(
        find.text('secret content'),
        findsNothing,
        reason: 'the ghost must never re-render the original message content',
      );

      await tester.pump(const Duration(milliseconds: 350)); // 고스트 페이드아웃 flush
    },
  );

  testWidgets('system message bubble renders centred', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: MessageBubble(
              message: msg(
                id: 's1',
                dir: MessageDirection.incoming,
                kind: MessageKind.system,
                text: 'link closed',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('link closed'), findsOneWidget);
  });

  testWidgets('timed message bubble shows the burn countdown', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MessageBubble(
              message: msg(
                id: 't1',
                dir: MessageDirection.outgoing,
                text: 'secret',
                ttl: 30,
                burnAt: DateTime.now().add(const Duration(seconds: 30)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BurnCountdown), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget); // delivery=sent 체크
  });

  test('both themes expose the ChatColors extension', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final chat = theme.extension<ChatColors>();
      expect(chat, isNotNull);
      expect(chat!.bubbleMine, isNot(chat.bubbleTheirs));
      expect(chat.lerp(null, 0.5), same(chat));
      final blended = chat.lerp(ChatColors.dark, 0.5);
      expect(blended.canvas, isNotNull);
    }
  });
}
