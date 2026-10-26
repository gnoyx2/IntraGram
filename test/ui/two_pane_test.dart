import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_commands.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 목록의 탐색 레이더가 계속 돌아서 pumpAndSettle이 안 끝남: 전환 시간만큼만 돌림
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

Future<Harness> _pumpHome(WidgetTester tester, Size size) async {
  _setSize(tester, size);
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store
    ..upsertConversation(conv('c1'))
    ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'));
  // 앱처럼 루트에 AppCommands를 둠 (Esc·⌘W 닫기를 거기서 받음)
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    h.wrap(
      const HomeScreen(),
      navigatorKey: key,
      builder: (context, child) => AppCommands(
        navigatorKey: key,
        unlocked: true,
        onNewConnection: (_) {},
        child: child!,
      ),
    ),
  );
  await tester.pump();
  return h;
}

void main() {
  testWidgets('a wide window keeps the list next to the open chat', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(1280, 800));
    expect(find.text('No chat open'), findsOneWidget);

    await tester.tap(find.byType(ConversationTile));
    await _settle(tester);
    expect(find.byType(ConversationTile), findsOneWidget);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
    expect(
      tester.widget<ConversationTile>(find.byType(ConversationTile)).selected,
      isTrue,
    );
    // 말풍선이 창 전체가 아니라 오른쪽 창 폭을 기준으로 잼
    expect(
      tester.getTopLeft(find.byType(ChatRoomScreen)).dx,
      greaterThanOrEqualTo(360),
    );

    // Esc는 오른쪽 창의 대화만 닫고 목록은 그대로 둠
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(ConversationTile), findsOneWidget);
    expect(find.text('No chat open'), findsOneWidget);
  });

  testWidgets('narrowing the window keeps the open chat, back shows the list', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(1280, 800));
    await tester.tap(find.byType(ConversationTile));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'draft');

    _setSize(tester, const Size(600, 800));
    await _settle(tester);
    expect(find.byType(ConversationTile), findsNothing);
    expect(find.text('draft'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(ConversationTile), findsOneWidget);
  });

  testWidgets('a narrow window still opens the chat full screen', (
    tester,
  ) async {
    await _pumpHome(tester, const Size(600, 800));
    await tester.tap(find.byType(ConversationTile));
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(find.byType(ConversationTile), findsNothing);
    expect(find.text('No chat open'), findsNothing);
  });

  testWidgets('ending the chat in the pane drops it from the pane', (
    tester,
  ) async {
    final h = await _pumpHome(tester, const Size(1280, 800));
    await tester.tap(find.byType(ConversationTile));
    await _settle(tester);
    h.store.wipeConversation('c1');
    await _settle(tester);
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.text('No chat open'), findsOneWidget);
  });

  testWidgets('Ctrl+Tab steps to the next chat in the pane', (tester) async {
    final h = await _pumpHome(tester, const Size(1280, 800));
    h.store.upsertConversation(conv('c2').copyWith(peerAlias: 'cat-elk-31'));
    await _settle(tester);
    await tester.tap(find.byType(ConversationTile).first);
    await _settle(tester);
    bool selected(int i) => tester
        .widget<ConversationTile>(find.byType(ConversationTile).at(i))
        .selected;
    expect([selected(0), selected(1)], [true, false]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _settle(tester);
    expect([selected(0), selected(1)], [false, true]);
  });
}
