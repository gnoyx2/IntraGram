import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/chat_input.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  final haptics = <Object?>[];
  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('send haptic only fires for a nonempty enabled message', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            enabled: true,
            onSend: sent.add,
            onAttach: () {},
            onTypingChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(haptics, isEmpty);
    await tester.enterText(find.byType(TextField), '  hello  ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, ['hello']);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    await tester.tap(find.byIcon(Icons.send_rounded));
    expect(haptics, hasLength(1));
    await tester.pumpAndSettle();
  });

  for (final action in ['👍', 'Delete for me', 'Delete for everyone']) {
    testWidgets('$action uses one selection or destructive haptic', (
      tester,
    ) async {
      final h = Harness();
      addTearDown(h.dispose);
      // 모두에게서 지우기는 내 메시지에만 있음
      final message = msg(
        id: 'm1',
        dir: action == 'Delete for everyone'
            ? MessageDirection.outgoing
            : MessageDirection.incoming,
        text: 'hello',
      );
      h.store
        ..upsertConversation(conv('c1'))
        ..addMessage(message);
      await tester.pumpWidget(
        h.wrap(Scaffold(body: MessageBubble(message: message))),
      );
      await tester.longPress(find.text('hello'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(action));
      await tester.pumpAndSettle();
      haptics.clear();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(haptics, [
        action == '👍'
            ? 'HapticFeedbackType.selectionClick'
            : 'HapticFeedbackType.mediumImpact',
      ]);
      if (action != '👍') expect(h.store.messageById('m1'), isNull);
    });
  }

  testWidgets('an existing reaction toggles with one selection click', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    final message = msg(id: 'm1', dir: MessageDirection.incoming, text: 'hello')
        .copyWith(
          reactions: {
            'peer': {'👍'},
          },
        );
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(message);
    await tester.pumpWidget(
      h.wrap(Scaffold(body: MessageBubble(message: message))),
    );
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    expect(h.store.messageById('m1')!.reactions[h.identity.peerId], {'👍'});
  });
}
