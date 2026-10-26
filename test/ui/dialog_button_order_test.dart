import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/settings/pin_dialog.dart';
import 'package:intragram/store/vault.dart';

// Windows(Fluent) 대화상자는 주 동작이 맨 왼쪽, 취소가 맨 오른쪽. 다른 OS는 원래 순서(PIN 지우기 · 취소 · 저장)
class _Settings extends VaultSettingsNotifier {
  @override
  VaultSettings build() =>
      const VaultSettings(enabled: true, pinProtected: true);
}

void main() {
  Future<List<double>> centers(
    WidgetTester tester,
    TargetPlatform platform,
    List<String> labels,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultSettingsProvider.overrideWith(_Settings.new)],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          home: const Scaffold(body: PinDialog(alreadySet: true)),
        ),
      ),
    );
    return [for (final label in labels) tester.getCenter(find.text(label)).dx];
  }

  testWidgets('Windows puts Save first and Cancel last', (tester) async {
    final [save, remove, cancel] = await centers(
      tester,
      TargetPlatform.windows,
      ['Save', 'Remove PIN', 'Cancel'],
    );
    expect(save, lessThan(remove));
    expect(remove, lessThan(cancel));
  });

  testWidgets('Android keeps Remove PIN, Cancel, Save', (tester) async {
    final [remove, cancel, save] = await centers(
      tester,
      TargetPlatform.android,
      ['Remove PIN', 'Cancel', 'Save'],
    );
    expect(remove, lessThan(cancel));
    expect(cancel, lessThan(save));
  });

  test('every alert dialog orders its buttons per platform', () {
    // AppAlertDialog 정의 파일은 받은 actions를 그대로 넘기기만 해서 뺌
    final dialog = RegExp(r'(?<![A-Za-z])(?:App)?AlertDialog(\.adaptive)?\(');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('adaptive_dialog_action.dart'),
        );
    var dialogs = 0;
    for (final file in files) {
      final src = file.readAsStringSync();
      final count = dialog.allMatches(src).length;
      dialogs += count;
      expect(
        'actions: dialogActions('.allMatches(src).length,
        count,
        reason: file.path,
      );
    }
    expect(dialogs, greaterThan(10));
  });
}
