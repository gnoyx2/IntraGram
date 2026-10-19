import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:intragram/core/native_open.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 메시지 속 링크는 바로 안 열고, 실제로 갈 호스트(퓨니코드)를 보여 주고 물음.
// 양방향 제어 문자가 든 주소는 링크로 만들지 않음
void main() {
  const en = S(AppLang.en);

  Future<List<Uri>> pumpBubble(WidgetTester tester, String text) async {
    final opened = <Uri>[];
    NativeOpen.launchUrlOverride = (uri, {required mode}) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => NativeOpen.launchUrlOverride = launchUrl);
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
    return opened;
  }

  testWidgets('a link asks first and names the real host', (tester) async {
    const url = 'https://аpple.com/login';
    final opened = await pumpBubble(tester, 'see $url now');

    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();
    expect(find.text('xn--pple-43d.com'), findsOneWidget);
    expect(find.text(en.t('link.lookalike')), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    await tester.tap(find.text(en.t('common.cancel')));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);

    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.t('link.open')));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
  });

  testWidgets('a plain host gets no look-alike warning', (tester) async {
    const url = 'https://example.com/a';
    await pumpBubble(tester, url);
    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text(en.t('link.lookalike')), findsNothing);
  });

  // 확인 창의 퓨니코드 계산은 길이 제곱이라 아주 긴 주소 한 번 탭으로 UI가 멈출 수 있었음
  testWidgets('an address longer than 2048 characters is not a link', (
    tester,
  ) async {
    // 목록 없이 말풍선만 띄우니 긴 글이 다 들어가게 화면을 키움
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final url = 'https://${'é' * 3000}.com/';
    await pumpBubble(tester, url);
    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();
    expect(find.text(en.t('link.openTitle')), findsNothing);
  });

  testWidgets('an address with a bidi control is not a link', (tester) async {
    const url = 'https://ex\u202Eelpmaxe.com/';
    await pumpBubble(tester, 'go $url x');
    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();
    expect(find.text(en.t('link.openTitle')), findsNothing);
  });
}
