import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/message_list.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  for (final target in ['m45', 'm1']) {
    testWidgets('Reduce Motion focuses $target without animated scrolling', (
      tester,
    ) async {
      final h = Harness();
      addTearDown(h.dispose);
      final messages = List.generate(
        50,
        (i) =>
            msg(id: 'm$i', dir: MessageDirection.incoming, text: 'Message $i'),
      );
      Widget view(String? focus) => h.wrap(
        Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: MessageList(messages: messages, focusMessageId: focus),
          ),
        ),
      );
      await tester.pumpWidget(view(null));
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(300);
      await tester.pumpAndSettle();
      await tester.pumpWidget(view(target));
      await tester.pump();
      await tester.pump();
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      expect(
        find.text('Message ${target.substring(1)}').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  }
  for (final reduceMotion in [false, true]) {
    testWidgets(
      'jump to latest ${reduceMotion ? 'is immediate with Reduce Motion' : 'animates for 250ms'}',
      (tester) async {
        final h = Harness();
        addTearDown(h.dispose);
        await tester.pumpWidget(
          h.wrap(
            Scaffold(
              body: MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: MessageList(
                  messages: List.generate(
                    40,
                    (i) => msg(
                      id: 'm$i',
                      dir: MessageDirection.incoming,
                      text: 'Message $i\nSecond line\nThird line',
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final controller = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        controller.jumpTo(600);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FloatingActionButton));

        if (reduceMotion) {
          expect(controller.offset, 0);
        } else {
          expect(controller.offset, 600);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 125));
          expect(controller.offset, greaterThan(0));
          expect(controller.offset, lessThan(600));
          await tester.pump(const Duration(milliseconds: 125));
          expect(controller.offset, 0);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
