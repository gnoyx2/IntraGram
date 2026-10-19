import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/features/chat/widgets/chat_app_bar.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

import '../support/contrast.dart';
import '_harness.dart';

void main() {
  testWidgets('320dp Korean retry metadata fits at 200% text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    final message = msg(
      id: 'failed',
      dir: MessageDirection.outgoing,
      text: '본문',
      createdAt: DateTime(2026, 1, 1, 23, 59),
      ttl: 60,
      burnAt: DateTime.now().add(const Duration(seconds: 60)),
    ).copyWith(delivery: DeliveryState.failed);
    h.store.upsertConversation(conv('c1'));
    await tester.pumpWidget(
      h.wrap(
        LocaleScope(
          lang: AppLang.ko,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                alwaysUse24HourFormat: false,
              ),
              child: Scaffold(body: MessageBubble(message: message)),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('60'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final clock = find.text('오후 11:59');
    final clockParagraph = tester.renderObject<RenderParagraph>(clock);
    // 메타 행은 OS 200%까지 따라 커짐 (예전 1.35배 상한은 1.4.4에 못 미쳤음)
    expect(clockParagraph.textScaler.scale(12), closeTo(24, 0.001));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.refresh)).size,
      closeTo(28, 0.001),
    );
    // 말풍선 글은 어절 줄바꿈용 단어 결합 문자가 음절 사이에 들어간 채로 그려짐
    final body = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('본\u2060문'),
        matching: find.byType(RichText),
      ),
    );
    expect(body.textScaler.scale(15), 30);
  });

  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets('${theme.brightness.name} reconnect text stays at AAA', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: OfflineBanner(onReconnect: () async {})),
        ),
      );
      final text = tester.renderObject<RenderParagraph>(find.text('Reconnect'));
      final ink = (text.text as TextSpan).style!.color!;
      final background = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(OfflineBanner),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(contrastRatio(ink, background.color!), greaterThanOrEqualTo(7));
    });
  }
}
