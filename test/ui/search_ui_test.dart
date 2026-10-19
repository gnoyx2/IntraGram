import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/widgets/chat_app_bar.dart';
import 'package:intragram/features/search/search_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  testWidgets('search screen finds a message by text', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(
        msg(
          id: 'm1',
          dir: MessageDirection.incoming,
          text: 'the quick brown fox',
        ),
      );

    await tester.pumpWidget(h.wrap(const SearchScreen()));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'brown');
    await tester.pump();

    expect(find.textContaining('quick brown fox'), findsOneWidget);
  });

  testWidgets('in-chat search steps through hits and closes cleanly', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(
        msg(
          id: 'm1',
          dir: MessageDirection.incoming,
          text: 'alpha one',
          createdAt: DateTime(2026, 1, 1, 10, 0),
        ),
      )
      ..addMessage(
        msg(
          id: 'm2',
          dir: MessageDirection.incoming,
          text: 'beta two',
          createdAt: DateTime(2026, 1, 1, 10, 1),
        ),
      )
      ..addMessage(
        msg(
          id: 'm3',
          dir: MessageDirection.outgoing,
          text: 'alpha three',
          createdAt: DateTime(2026, 1, 1, 10, 2),
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search in chat'));
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search in chat',
    );
    expect(searchField, findsOneWidget);
    await tester.enterText(searchField, 'alpha');
    await tester.pumpAndSettle();

    // 매치 둘(m1, m3): 카운터는 가장 최신에서 시작
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Search in chat'), findsNothing);
    expect(find.byType(ChatOverflowMenu), findsOneWidget);
  });
}
