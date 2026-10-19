import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 데스크톱에서 말풍선에 마우스를 올리면 답장·반응·더보기 버튼이 옆에 뜸 (우클릭을 몰라도 동작을 찾음).
// 터치 기기엔 안 그림
void main() {
  Future<List<String>> pump(WidgetTester tester) async {
    final replies = <String>[];
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: MessageBubble(
              message: msg(
                id: 'm1',
                dir: MessageDirection.incoming,
                text: 'hello',
              ),
              onReply: replies.add,
            ),
          ),
        ),
      ),
    );
    return replies;
  }

  testWidgets('hovering a bubble on desktop shows reply, react and more', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final replies = await pump(tester);
      final reply = find.byTooltip('Reply');
      expect(reply.hitTestable(), findsNothing, reason: 'hidden until hover');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('hello')));
      await tester.pumpAndSettle();
      expect(reply.hitTestable(), findsOneWidget);
      expect(find.byTooltip('More reactions').hitTestable(), findsOneWidget);
      expect(find.byTooltip('More').hitTestable(), findsOneWidget);

      await tester.tap(reply);
      await tester.pumpAndSettle();
      expect(replies, ['m1']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('touch platforms keep the bubble as it was', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Reply'), findsNothing);
  });
}
