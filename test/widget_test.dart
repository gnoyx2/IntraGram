import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/l10n/strings.dart';

void main() {
  testWidgets('home screen shows the brand and slogan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeScreen())),
    );
    await tester.pump();

    expect(find.text('Intragram'), findsOneWidget);
    expect(find.textContaining('No cloud'), findsOneWidget);
    expect(find.text('Active chats'), findsOneWidget);
  });

  testWidgets('home screen renders Korean under a ko LocaleScope', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LocaleScope(lang: AppLang.ko, child: HomeScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('클라우드 없음'), findsOneWidget);
    expect(find.text('진행 중인 대화'), findsOneWidget);
  });
}
