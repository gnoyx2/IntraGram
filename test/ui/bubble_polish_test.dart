import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/motion.dart';

import '../support/contrast.dart';
import '_harness.dart';

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    for (final direction in MessageDirection.values) {
      testWidgets(
        '${theme.brightness.name} ${direction.name}: quote text stays at AAA',
        (tester) async {
          final h = Harness();
          addTearDown(h.dispose);
          h.store
            ..upsertConversation(conv('c1'))
            ..addMessage(
              msg(
                id: 'parent',
                dir: MessageDirection.incoming,
                text: 'quoted preview',
              ),
            );
          await tester.pumpWidget(
            h.wrap(
              Theme(
                data: theme,
                child: Scaffold(
                  body: MessageBubble(
                    message: msg(
                      id: 'reply',
                      dir: direction,
                      text: 'reply body',
                      replyToId: 'parent',
                    ),
                  ),
                ),
              ),
            ),
          );
          final preview = find.text('quoted preview');
          final tint = tester
              .widgetList<Container>(
                find.ancestor(of: preview, matching: find.byType(Container)),
              )
              .map((w) => w.decoration)
              .whereType<BoxDecoration>()
              .single
              .color!;
          final chat = theme.extension<ChatColors>()!;
          final backgrounds = direction == MessageDirection.outgoing
              ? [chat.bubbleMineTop, chat.bubbleMine]
              : [chat.bubbleTheirs];
          // 실제 위젯의 색을 읽고 인용 틴트까지 합성해서 그라디언트 양끝을 검증함
          for (final finder in [preview, find.text('bob-owl-22')]) {
            final ink = tester.widget<Text>(finder).style!.color!;
            for (final background in backgrounds) {
              expect(
                contrastRatio(ink, Color.alphaBlend(tint, background)),
                greaterThanOrEqualTo(7),
              );
            }
          }
        },
      );
    }
  }

  testWidgets(
    'bubble tap and long press each haptic once, scrolling does not',
    (tester) async {
      final h = Harness();
      addTearDown(h.dispose);
      h.store.upsertConversation(conv('c1'));
      final haptics = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        h.wrap(
          Scaffold(
            body: ListView(
              children: [
                MessageBubble(
                  message: msg(
                    id: 'message',
                    dir: MessageDirection.incoming,
                    text: 'touch target',
                  ),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('touch target'));
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        AppMotion.pressedScale,
      );
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      haptics.clear();

      await tester.drag(find.text('touch target'), const Offset(0, -30));
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);

      await tester.drag(find.byType(ListView), const Offset(0, 80));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('touch target'));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    },
  );
}
