import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/widgets/message_list.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/widgets/keyboard_access.dart';

import '_harness.dart';

// 데스크톱 키보드만으로 대화 이력을 읽고 말풍선 동작을 열 수 있어야 함 (WCAG 2.1.1)
void main() {
  const en = S(AppLang.en);
  final history = List.generate(
    60,
    (i) => msg(id: 'm$i', dir: MessageDirection.incoming, text: 'Message $i'),
  );

  Future<Harness> pumpList(WidgetTester tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    await tester.pumpWidget(
      h.wrap(Scaffold(body: MessageList(messages: history))),
    );
    await tester.pump();
    return h;
  }

  FocusNode bubbleFocus(WidgetTester tester, String text) =>
      Focus.of(tester.element(find.text(text)));

  double offset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  for (final key in <List<LogicalKeyboardKey>>[
    [LogicalKeyboardKey.enter],
    [LogicalKeyboardKey.contextMenu],
    [LogicalKeyboardKey.shift, LogicalKeyboardKey.f10],
  ]) {
    testWidgets('${key.last.keyLabel} on a focused bubble opens its actions', (
      tester,
    ) async {
      await pumpList(tester);
      bubbleFocus(tester, 'Message 59').requestFocus();
      await tester.pump();
      for (final k in key) {
        await tester.sendKeyDownEvent(k);
      }
      for (final k in key.reversed) {
        await tester.sendKeyUpEvent(k);
      }
      await tester.pumpAndSettle();
      expect(find.text(en.t('msg.reply')), findsOneWidget);
    });
  }

  testWidgets('PageUp, Home and End move through the history', (tester) async {
    await pumpList(tester);
    bubbleFocus(tester, 'Message 59').requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(offset(tester), greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(offset(tester), state.position.maxScrollExtent);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(offset(tester), 0);
  });

  testWidgets('the hidden jump button is not a tab stop', (tester) async {
    await pumpList(tester);
    final exclude = tester.widget<ExcludeFocus>(
      find.ancestor(
        of: find.byType(FloatingActionButton),
        matching: find.byType(ExcludeFocus),
      ),
    );
    expect(exclude.excluding, isTrue);
  });

  testWidgets('the wrapper around the message field is not a tab stop', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    final wrappers = tester
        .widgetList<Focus>(
          find.ancestor(
            of: find.byType(TextField),
            matching: find.byType(Focus),
          ),
        )
        .where((f) => f.onKeyEvent != null);
    expect(wrappers, isNotEmpty);
    expect(wrappers.every((f) => f.canRequestFocus == false), isTrue);
  });

  testWidgets('Shift+F10 on a home tile opens its actions', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    var menus = 0;
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: ConversationTile(
            conversation: conv('c1'),
            onTap: () {},
            onMenu: ([_]) => menus++,
          ),
        ),
      ),
    );
    Focus.of(tester.element(find.text('bob-owl-22'))).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    expect(menus, 1);
  });

  testWidgets('keyboard focus gets a ring that pointer use does not', (
    tester,
  ) async {
    final button = FocusNode();
    addTearDown(button.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FocusRingLayer(child: child!),
        home: Scaffold(
          body: Center(
            child: IconButton(
              focusNode: button,
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );
    button.requestFocus();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(FocusRingLayer.ringKey), findsNothing);

    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(FocusRingLayer.ringKey), findsOneWidget);
  });

  testWidgets('a focus that wraps the screen gets no ring', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FocusRingLayer(child: child!),
        home: const Focus(autofocus: true, child: Scaffold()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(FocusRingLayer.ringKey), findsNothing);
  });
}
