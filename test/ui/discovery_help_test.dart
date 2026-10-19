import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/home/widgets/discovery_help.dart';
import 'package:intragram/l10n/strings.dart';

// 아무도 안 보일 때의 점검표: 펼치면 원인별 확인 항목과 핫스팟 우회가 보이고,
// iOS·macOS면 로컬 네트워크 설정을 바로 엶. 플랫폼은 테스트를 돌리는 호스트가 아니라
// debugDefaultTargetPlatformOverride로 정함
void main() {
  const en = S(AppLang.en);

  testWidgets('the checklist lists the causes and the hotspot way out', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DiscoveryHelp())),
      );
      expect(find.text(en.t('discoveryHelp.title')), findsOneWidget);
      expect(find.text(en.t('discoveryHelp.hotspot')), findsNothing);

      await tester.tap(find.text(en.t('discoveryHelp.title')));
      await tester.pumpAndSettle();

      for (final key in [
        'discoveryHelp.sameWifi',
        'discoveryHelp.appOpen',
        'discoveryHelp.localNetwork',
        'discoveryHelp.hotspot',
        'discoveryHelp.byIp',
      ]) {
        expect(find.text(en.t(key)), findsOneWidget, reason: key);
      }
      expect(find.text(en.t('settings.open')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Linux has no local network line and no settings to open', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DiscoveryHelp())),
      );
      await tester.tap(find.text(en.t('discoveryHelp.title')));
      await tester.pumpAndSettle();

      expect(find.text(en.t('discoveryHelp.hotspot')), findsOneWidget);
      expect(find.text(en.t('discoveryHelp.localNetwork')), findsNothing);
      expect(find.text(en.t('settings.open')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
