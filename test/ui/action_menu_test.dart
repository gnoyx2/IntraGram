import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

final _en = S(AppLang.en);

Future<void> _pumpChat(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = Harness();
  addTearDown(h.dispose);
  h.store
    ..upsertConversation(conv('c1'))
    ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'));
  await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
  await tester.pump();
}

void main() {
  testWidgets('right-clicking a bubble opens the menu at the cursor', (
    tester,
  ) async {
    await _pumpChat(tester);
    final at = tester.getCenter(find.text('hi'));
    await tester.tapAt(at, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    final reply = find.text(_en.t('msg.reply'));
    expect(reply, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // 창 맨 아래 시트가 아니라 커서 근처
    expect((tester.getCenter(reply).dy - at.dy).abs(), lessThan(300));

    // 메뉴에서 고른 값도 시트와 같은 길로 돌아옴: 답장 줄이 뜸
    await tester.tap(reply);
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsNWidgets(2));
  });

  testWidgets('a long press still opens the bottom sheet', (tester) async {
    await _pumpChat(tester);
    await tester.longPress(find.text('hi'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text(_en.t('msg.reply')), findsOneWidget);
  });
}
