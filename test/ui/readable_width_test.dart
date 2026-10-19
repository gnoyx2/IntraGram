import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void _fullHd(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('settings text stays in a 720 column on a wide window', (
    tester,
  ) async {
    _fullHd(tester);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const SettingsScreen()));
    await tester.pump();

    final tile = find.byType(SwitchListTile).first;
    expect(tester.getSize(tile).width, 720);
    expect(tester.getTopLeft(tile).dx, 600);
  });

  testWidgets('a wide chat keeps bubbles and the input in one column', (
    tester,
  ) async {
    _fullHd(tester);
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1'))
      ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'))
      ..addMessage(msg(id: 'm2', dir: MessageDirection.outgoing, text: 'yo'));
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    // 가운데 840 열 = x 540..1380
    final bubbles = find.byType(MessageBubble);
    final theirs = tester.getRect(bubbles.at(0));
    final mine = tester.getRect(bubbles.at(1));
    expect(theirs.left, greaterThanOrEqualTo(540));
    expect(mine.right, lessThanOrEqualTo(1380));
    final input = tester.getRect(find.byType(TextField).last);
    expect(input.left, greaterThanOrEqualTo(540));
    expect(input.right, lessThanOrEqualTo(1380));
  });
}
