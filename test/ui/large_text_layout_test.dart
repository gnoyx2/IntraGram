import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_input.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/widgets/identity_card.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// iOS 가장 큰 글씨(본문 3.12배)에서 방 화면: 중계·오프라인·미검증 배너가 화면을 다 먹어 메시지 목록이
// 0이 되고 입력창이 잘렸음. 배너 묶음은 화면의 30%까지만 차지하고 안에서 스크롤함
void main() {
  testWidgets('a room at 3.12x text leaves room for messages and the '
      'composer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(
      conv('r1').copyWith(
        isRoom: true,
        hostAlias: 'ann-fox-12',
        memberCount: 3,
        online: false,
        members: const {'m1': RoomMember(alias: 'blue-otter-38')},
      ),
    );

    await tester.pumpWidget(
      h.wrap(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(3.12),
            disableAnimations: true,
          ),
          child: ChatRoomScreen(conversationId: 'r1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull, reason: 'no overflow');
    final input = tester.getRect(find.byType(ChatInput));
    expect(input.bottom, lessThanOrEqualTo(844));
    expect(input.top, greaterThan(844 * 0.3), reason: 'banners are capped');

    // 잘린 상태 줄은 길게 누르거나 올려 두면 전문이 뜸 (같은 내용은 중계 배너에도 있음)
    final status = tester.widget<Text>(find.textContaining('via ann-fox-12'));
    expect(find.byTooltip(status.data!), findsOneWidget);
  });

  testWidgets('my name on the home card wraps instead of cutting off at '
      '3.12x', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(3.12),
          ),
          child: Scaffold(
            body: IdentityCard(
              identity: h.identity,
              server: const ServerState(
                running: true,
                host: '192.168.1.2',
                port: 7890,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final name = tester.renderObject<RenderParagraph>(find.text('me-host-10'));
    expect(name.didExceedMaxLines, isFalse);
  });

  testWidgets('a screen reader hears the room title before the relay '
      'notice', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(
      conv('r1').copyWith(isRoom: true, hostAlias: 'ann-fox-12'),
    );
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'r1')));
    await tester.pump();
    final labels = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.label)
        .toList();
    final title = labels.indexWhere((l) => l.contains('via ann-fox-12'));
    final notice = labels.indexWhere((l) => l.startsWith('Host relay'));
    expect(title, isNonNegative);
    expect(notice, greaterThan(title));
    semantics.dispose();
  });
}
