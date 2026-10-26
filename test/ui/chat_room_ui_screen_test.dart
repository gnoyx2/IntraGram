import 'package:flutter/cupertino.dart' show CupertinoDialogAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  testWidgets('chat room renders bubbles for both directions', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'))
      ..addMessage(
        msg(id: 'm2', dir: MessageDirection.outgoing, text: 'hello back'),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    expect(find.text('hi'), findsOneWidget);
    expect(find.text('hello back'), findsOneWidget);
    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.text('verified · end-to-end encrypted'), findsOneWidget);
    expect(find.textContaining('Host relay'), findsNothing);
  });

  testWidgets('a group room shows the host relay notice', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(
      conv('r1').copyWith(isRoom: true, hostAlias: 'ann-fox-12'),
    );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'r1')));
    await tester.pump();

    expect(
      find.textContaining('Host relay (hop-by-hop), not end-to-end'),
      findsOneWidget,
    );
  });

  testWidgets('an empty room I host explains instead of offering reconnect', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('r1').copyWith(isRoom: true, online: false))
      ..upsertConversation(
        conv('r2').copyWith(isRoom: true, online: false, hostAlias: 'ann'),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'r1')));
    await tester.pump();
    expect(find.textContaining('Everyone has left'), findsOneWidget);
    expect(find.text('Reconnect'), findsNothing);

    // 남이 연 방은 호스트 하나만 다시 걸면 돼서 버튼이 그대로 있음
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'r2')));
    await tester.pump();
    expect(find.text('Reconnect'), findsOneWidget);
  });

  testWidgets('a room menu has no auto-accept item', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('r1').copyWith(isRoom: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'r1')));
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 방 파일은 늘 물어봐서 눌러도 아무 일 없는 토글을 안 보여줌
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    expect(find.text('Auto-accept files'), findsNothing);
  });

  testWidgets('a message URL renders as a tappable link span', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(
        msg(
          id: 'm1',
          dir: MessageDirection.incoming,
          text: 'try https://192.168.1.9:7890/wiki now',
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    // linkify가 문자열을 스팬으로 쪼개도 URL 스팬은 화면에 있음
    expect(
      find.textContaining('192.168.1.9:7890/wiki', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(MessageBubble), findsOneWidget);
  });

  testWidgets('message list separates messages by day', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(
        msg(
          id: 'd1',
          dir: MessageDirection.incoming,
          text: 'earlier',
          createdAt: yesterday,
        ),
      )
      ..addMessage(
        msg(
          id: 'd2',
          dir: MessageDirection.incoming,
          text: 'later',
          createdAt: today,
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('opening with unread shows the New messages divider', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(
      conv('c1', secure: true, verified: true, unread: 2),
    );
    h.store
      ..addMessage(
        msg(id: 'r1', dir: MessageDirection.outgoing, text: 'old sent'),
      )
      ..addMessage(
        msg(id: 'u1', dir: MessageDirection.incoming, text: 'unread one'),
      )
      ..addMessage(
        msg(id: 'u2', dir: MessageDirection.incoming, text: 'unread two'),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    expect(find.text('New messages'), findsOneWidget);
  });

  testWidgets('chat room shows the unverified banner and SAS dialog', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, sas: '314159'));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Code not verified'), findsOneWidget);
    expect(find.byIcon(Icons.gpp_maybe), findsNWidgets(2)); // 배너 + 앱바

    await tester.tap(find.byTooltip('Check security code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Security code'), findsOneWidget);
    expect(find.textContaining('314 159'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    // 매치 버튼은 플랫폼별로 위젯 타입이 다름(iOS/macOS는 CupertinoDialogAction,
    // 그 외엔 FilledButton.icon): 둘 다 커버
    await tester.tap(
      find.ancestor(
        of: find.text('They match'),
        matching: find.byWidgetPredicate(
          (w) => w is CupertinoDialogAction || w is FilledButton,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 나만 눌렀고 상대(라이브 링크가 없어서 이 테스트엔 없음)는 아직 확인
    // 안 함: verified는 여전히 false, "대기중" 아이콘으로 바뀜
    expect(h.store.conversation('c1')!.localVerified, isTrue);
    expect(h.store.conversation('c1')!.verified, isFalse);
    expect(find.byIcon(Icons.pending), findsNWidgets(2)); // 배너 + 앱바
  });
}
