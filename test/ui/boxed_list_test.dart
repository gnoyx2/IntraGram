import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/store/vault.dart';

import '_harness.dart';

// Linux(libadwaita) 설정은 절마다 줄을 둥근 상자 하나에 담음. 다른 OS는 줄을 그대로 늘어놓음
void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    final dir = Directory.systemTemp.createTempSync('intragram_boxed');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      h.wrap(
        const SettingsScreen(),
        overrides: [
          vaultProvider.overrideWithValue(
            Vault(resolveDir: () async => dir.path),
          ),
        ],
      ),
    );
  }

  Finder boxOf(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Card));

  testWidgets(
    'Linux groups each settings section in one box',
    (tester) async {
      await pumpSettings(tester);
      expect(boxOf('Keep chats on this device'), findsOneWidget);
      expect(
        tester.widget(boxOf('Keep chats on this device')),
        same(tester.widget(boxOf('Saved chats'))),
      );
      await tester.scrollUntilVisible(find.text('Language'), 200);
      expect(boxOf('Language'), findsOneWidget);
      expect(find.byType(Divider), findsWidgets);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'other platforms keep flat rows',
    (tester) async {
      await pumpSettings(tester);
      expect(boxOf('Keep chats on this device'), findsNothing);
      await tester.scrollUntilVisible(find.text('Language'), 200);
      expect(boxOf('Language'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
