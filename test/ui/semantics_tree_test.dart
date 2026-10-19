import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 스크린 리더: 우클릭·키보드 내리기용 제스처가 이름 없는 '탭' 칸을 만들지 않고, 말풍선은 보낸이·본문과
// 답장·복사·반응·삭제 동작을 한 노드에 가짐 (예전엔 동작은 이름 없는 바깥 칸에 있었음)
void main() {
  testWidgets('home has no unlabeled tap targets', (tester) async {
    final handle = tester.ensureSemantics();
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const HomeScreen()));
    await tester.pump();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('a chat bubble carries its actions on the readable node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(
        msg(id: 'm1', dir: MessageDirection.outgoing, text: 'see you at 6'),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    final node = tester.getSemantics(find.textContaining('see you at 6'));
    final actions = node.getSemanticsData().customSemanticsActionIds ?? [];
    final labels = [
      for (final id in actions) CustomSemanticsAction.getAction(id)?.label,
    ];
    expect(
      labels,
      containsAll([
        'Reply',
        'Copy text',
        'More reactions',
        'Delete for everyone',
      ]),
    );
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );
    handle.dispose();
  });
}
