import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/features/chat/widgets/typing_dots.dart';
import 'package:intragram/features/home/widgets/home_sections.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

import '_harness.dart';

// 화면에 그려진 너비 / 레이아웃 너비 = 조상 변환들의 누적 배율
double _scaleOf(WidgetTester tester, Finder finder) =>
    tester.getRect(finder).width / tester.getSize(finder).width;

DateTime _at(int minute) => DateTime(2026, 1, 1, 10, minute);

const _incoming = MessageDirection.incoming;
const _outgoing = MessageDirection.outgoing;

void main() {
  testWidgets('a new message pops in once, not again after scrolling back', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    for (var i = 0; i < 40; i++) {
      h.store.addMessage(
        msg(id: 'old$i', dir: _incoming, text: 'old $i', createdAt: _at(i)),
      );
    }
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    h.store.addMessage(
      msg(id: 'fresh', dir: _incoming, text: 'fresh', createdAt: _at(45)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_scaleOf(tester, find.text('fresh')), lessThan(1));
    await tester.pump(const Duration(seconds: 1));
    expect(_scaleOf(tester, find.text('fresh')), 1);

    // 캐시 범위 밖까지 올려서 행을 버리게 한 뒤 다시 내려와 새로 빌드시킴
    final list = find.byWidgetPredicate((w) => w is ListView && w.reverse);
    await tester.drag(list, const Offset(0, 3000));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('fresh'), findsNothing);
    await tester.drag(list, const Offset(0, -3000));
    await tester.pump();
    expect(_scaleOf(tester, find.text('fresh')), 1);
  });

  testWidgets('reactions already on a bubble stay put, new ones pop in', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(
        msg(id: 'm', dir: _incoming, text: 'hi').copyWith(
          reactions: {
            'p1': {'👍'},
          },
        ),
      )
      ..addMessage(
        msg(id: 'bare', dir: _incoming, text: 'bare', createdAt: _at(40)),
      );
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    expect(_scaleOf(tester, find.text('👍')), 1);

    h.store
      ..applyReaction('m', 'p2', '🔥', on: true)
      // 반응이 하나도 없던 말풍선의 첫 반응도 튀어나와야 함
      ..applyReaction('bare', 'p2', '😂', on: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_scaleOf(tester, find.text('🔥')), lessThan(1));
    expect(_scaleOf(tester, find.text('😂')), lessThan(1));
    expect(_scaleOf(tester, find.text('👍')), 1);
  });

  testWidgets('a failed message keeps a compact meta row and retries on tap', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    final sent = msg(id: 'sent', dir: _outgoing, text: 'sent fine');
    final failed = msg(
      id: 'bad',
      dir: _outgoing,
      text: 'not sent',
      createdAt: _at(31),
    ).copyWith(delivery: DeliveryState.failed);
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(sent)
      ..addMessage(failed);
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: Column(
            children: [
              MessageBubble(message: sent),
              MessageBubble(message: failed),
            ],
          ),
        ),
      ),
    );

    Finder metaRow(String body, String clock) => find
        .ancestor(
          of: find.descendant(
            of: find.ancestor(
              of: find.text(body),
              matching: find.byType(MessageBubble),
            ),
            matching: find.text(clock),
          ),
          matching: find.byType(Row),
        )
        .first;
    expect(
      tester.getSize(metaRow('not sent', '10:31 AM')).height,
      tester.getSize(metaRow('sent fine', '10:30 AM')).height,
    );

    // 다시 보내기 표시는 작아도 탭 영역은 말풍선 전체
    await tester.tap(find.text('not sent'));
    await tester.pump();
    expect(h.store.messageById('bad'), isNull);
    expect(h.store.messages('c1').map((m) => m.text), contains('not sent'));
  });

  testWidgets('the typing indicator wears the incoming bubble shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: TypingDots()),
      ),
    );
    final context = tester.element(find.byType(TypingDots));
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(TypingDots),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      box.decoration,
      bubbleDecoration(
        chat: context.chat,
        scheme: Theme.of(context).colorScheme,
        mine: false,
        joinsPrevious: false,
        joinsNext: false,
      ),
    );
  });

  testWidgets('a section header wraps instead of truncating on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const label = 'On this network — 0 devices found';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(
            label,
            trailing: SizedBox(width: 140, height: 40),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('the quick reaction row splits a narrow phone evenly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    final ping = msg(id: 'm1', dir: _incoming, text: 'ping');
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(ping);
    await tester.pumpWidget(
      h.wrap(Scaffold(body: MessageBubble(message: ping))),
    );
    await tester.longPress(find.text('ping'));
    await tester.pumpAndSettle();

    // 넘치면 RenderFlex overflow 예외로 여기서 실패함
    expect(tester.takeException(), isNull);
    final slots = [
      for (final emoji in ['👍', '🙏'])
        tester.getSize(
          find.ancestor(of: find.text(emoji), matching: find.byType(InkWell)),
        ),
    ];
    expect(slots.first.width, slots.last.width);
    expect(slots.first.height, greaterThanOrEqualTo(48));
  });
}
