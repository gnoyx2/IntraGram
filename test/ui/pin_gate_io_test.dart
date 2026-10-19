import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/features/settings/pin_gate_screen.dart';
import 'package:intragram/store/vault.dart';

class _UnreadableVault extends Vault {
  @override
  Future<bool> isEncrypted() async => true;

  @override
  Future<VaultSnapshot?> load({String? pin}) async =>
      throw const FileSystemException('read blocked');
}

void main() {
  testWidgets('PIN gate reports disk failure and remains usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultProvider.overrideWithValue(_UnreadableVault())],
        child: const MaterialApp(home: PinGateScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(find.textContaining('Vault file could not be read'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
