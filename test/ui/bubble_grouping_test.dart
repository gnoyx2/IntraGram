import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/widgets/press_scale.dart';

import '_harness.dart';

void main() {
  testWidgets('one sender within 5 minutes joins into a corner group', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    const inc = MessageDirection.incoming;
    const out = MessageDirection.outgoing;
    DateTime at(int minute) => DateTime(2026, 1, 1, 10, minute);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(msg(id: 'a', dir: inc, text: 'a', createdAt: at(0)))
      ..addMessage(msg(id: 'b', dir: inc, text: 'b', createdAt: at(1)))
      ..addMessage(msg(id: 'c', dir: inc, text: 'c', createdAt: at(2)))
      ..addMessage(msg(id: 'd', dir: out, text: 'd', createdAt: at(3)))
      // 같은 발신자라도 5분 넘게 벌어지면 새 묶음
      ..addMessage(msg(id: 'e', dir: out, text: 'e', createdAt: at(20)))
      // 반응 칩이 달린 말풍선은 칩이 사이에 끼어 묶음을 끊음
      ..addMessage(
        msg(id: 'f', dir: inc, text: 'f', createdAt: at(21)).copyWith(
          reactions: {
            'p1': {'👍'},
          },
        ),
      )
      ..addMessage(msg(id: 'g', dir: inc, text: 'g', createdAt: at(22)));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    final joins = {
      for (final bubble in tester.widgetList<MessageBubble>(
        find.byType(MessageBubble),
      ))
        bubble.message.id: (bubble.joinsPrevious, bubble.joinsNext),
    };
    expect(joins, {
      'a': (false, true),
      'b': (true, true),
      'c': (true, false),
      'd': (false, false),
      'e': (false, false),
      'f': (false, false),
      'g': (false, false),
    });
  });

  group('PressScale', () {
    const box = Key('box');
    double scale(WidgetTester tester) =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

    // 실제 자식은 버튼·InkWell이라 늘 히트 테스트에 걸림. 빈 SizedBox는 안 걸려서 색 상자를 씀
    Future<void> pumpBox(WidgetTester tester, {bool enabled = true}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: PressScale(
                enabled: enabled,
                child: const ColoredBox(
                  key: box,
                  color: Color(0xFF2563EB),
                  child: SizedBox(width: 80, height: 40),
                ),
              ),
            ),
          ),
        );

    testWidgets('sinks after a held press and lets go when a drag starts', (
      tester,
    ) async {
      await pumpBox(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(box)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(scale(tester), 1, reason: 'a scroll may still start here');
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(tester), AppMotion.pressedScale);

      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(scale(tester), 1);
      await gesture.up();
    });

    testWidgets('a quick tap still pulses once', (tester) async {
      await pumpBox(tester);
      await tester.tap(find.byKey(box));
      await tester.pump();
      expect(scale(tester), AppMotion.pressedScale);
      await tester.pump(AppMotion.press);
      expect(scale(tester), 1);
    });

    testWidgets('a disabled button does not sink', (tester) async {
      await pumpBox(tester, enabled: false);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(box)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(scale(tester), 1);
      await gesture.up();
    });
  });
}
