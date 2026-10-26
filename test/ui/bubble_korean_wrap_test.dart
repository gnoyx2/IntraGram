import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 한글 말풍선은 음절이 아니라 어절에서 줄이 바뀜('보낼/게요' 대신 '보낼게요'). 화면 글에만 단어 결합 문자를
// 넣고, 스크린 리더와 복사는 원문을 씀
void main() {
  Future<void> pump(WidgetTester tester, String text) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: MessageBubble(
            message: msg(id: 'm1', dir: MessageDirection.incoming, text: text),
          ),
        ),
      ),
    );
  }

  String shown(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => r.text.toPlainText(includeSemanticsLabels: false))
      .firstWhere((t) => t.contains('\u2060'));

  testWidgets('Korean words are kept whole for line breaks', (tester) async {
    await pump(tester, '7쪽 보낼게요 지난주에 IntraGram으로');
    expect(
      shown(tester),
      '7\u2060쪽 보\u2060낼\u2060게\u2060요 지\u2060난\u2060주\u2060에 '
      'IntraGram\u2060으\u2060로',
    );
    expect(
      find.bySemanticsLabel(RegExp('7쪽 보낼게요 지난주에 IntraGram으로')),
      findsOneWidget,
    );
  });

  testWidgets('the joiner also applies next to a link', (tester) async {
    await pump(tester, '지난주 자료 https://example.com 확인해요');
    expect(shown(tester), contains('지\u2060난\u2060주'));
    expect(shown(tester), contains('https://example.com'));
  });
}
