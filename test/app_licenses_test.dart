import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_licenses.dart';
import 'package:intragram/features/settings/settings_screen.dart';

import 'ui/_harness.dart';

void main() {
  testWidgets('the license page lists IntraGram and the LocalSend notice', (
    tester,
  ) async {
    registerAppLicenses();
    final entries = await tester.runAsync(
      () => LicenseRegistry.licenses.toList(),
    );
    final ours = entries!.where((e) => e.packages.contains('IntraGram'));
    final text = ours.expand((e) => e.paragraphs).map((p) => p.text).join('\n');
    expect(text, contains('MIT License'));
    expect(text, contains('Apache License'));
    expect(text, contains('Tien Do Nam'));
    expect(entries.any((e) => e.packages.contains('LocalSend')), isTrue);
  });

  testWidgets('settings open the license page', (tester) async {
    // 설정 목록 끝까지 한 화면에 들어오게 세로로 길게
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const SettingsScreen()));
    await tester.pump();
    await tester.tap(find.text('Open-source licenses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
