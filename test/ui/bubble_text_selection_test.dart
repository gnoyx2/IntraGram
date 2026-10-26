import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 데스크톱은 말풍선 글 일부를 마우스로 골라 복사함. 복사는 통째 복사와 같은 OsPrivacy 길(클립보드 기록·
// 클라우드 제외)로 가고 화면에만 넣은 단어 결합 문자는 빠짐. 고른 글이 없으면 우클릭은 말풍선 메뉴
void main() {
  const privacy = MethodChannel('intragram/privacy');
  const text = 'hello 보낼게요 world';

  Future<List<String>> pump(WidgetTester tester) async {
    final copied = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(privacy, (call) async {
      if (call.method == 'copySensitive') copied.add(call.arguments as String);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(privacy, null));
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
                text: text,
              ),
              onReply: (_) {},
            ),
          ),
        ),
      ),
    );
    return copied;
  }

  // 화면 글(단어 결합 문자가 든 쪽)에서 '낼'자 가운데
  Offset wordCenter(WidgetTester tester) {
    final paragraph = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().contains('\u2060'));
    final index = paragraph.text.toPlainText().indexOf('낼');
    final caret = paragraph.getOffsetForCaret(
      TextPosition(offset: index),
      Rect.zero,
    );
    return paragraph.localToGlobal(caret + const Offset(4, 8));
  }

  Future<void> doubleClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  Future<void> desktop(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('a picked word copies through the private clipboard path', (
    tester,
  ) async {
    await desktop(() async {
      final copied = await pump(tester);
      await doubleClick(tester, wordCenter(tester));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(copied, ['보낼게요']);
      await tester.pump(OsPrivacy.clipboardLifetime); // 복사본 자동 지우기 타이머
    });
  });

  testWidgets('right-click on a selection offers copy, elsewhere the menu', (
    tester,
  ) async {
    await desktop(() async {
      final copied = await pump(tester);
      final word = wordCenter(tester);

      // 고른 글이 없으면 말풍선 동작 메뉴
      await tester.tapAt(
        word,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete for me'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // 고른 글 위에선 선택 영역의 복사 메뉴
      await doubleClick(tester, word);
      await tester.tapAt(
        word,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete for me'), findsNothing);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, ['보낼게요']);
      await tester.pump(OsPrivacy.clipboardLifetime);
    });
  });

  testWidgets('touch platforms keep whole-message copy only', (tester) async {
    await pump(tester);
    expect(find.byType(SelectionArea), findsNothing);
  });
}
