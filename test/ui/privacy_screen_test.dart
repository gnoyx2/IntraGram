import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/settings/privacy_screen.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/l10n/strings.dart';

import '_harness.dart';

// 스토어 심사는 앱 안에서 읽을 수 있는 개인정보 방침을 요구함: 인터넷 링크 없이 로컬 텍스트로 보여 주고,
// 저장소의 PRIVACY.md와 같은 내용
void main() {
  const en = S(AppLang.en);

  testWidgets('settings opens the privacy policy in the app', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const SettingsScreen()));
    await tester.pump();
    await tester.tap(find.text(en.t('privacy.title')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyScreen), findsOneWidget);
    expect(find.text(en.t('privacy.noServerBody')), findsOneWidget);
  });

  test('PRIVACY.md carries the same sections in both languages', () {
    final doc = File('PRIVACY.md').readAsStringSync();
    for (final lang in AppLang.values) {
      final s = S(lang);
      for (final key in PrivacyScreen.sections) {
        expect(doc, contains(s.t('privacy.${key}Title')), reason: '$lang $key');
        expect(doc, contains(s.t('privacy.${key}Body')), reason: '$lang $key');
      }
    }
  });
}
