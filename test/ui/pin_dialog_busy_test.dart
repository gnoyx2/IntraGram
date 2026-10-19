import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/settings/pin_dialog.dart';
import 'package:intragram/store/vault.dart';

class _Settings extends VaultSettingsNotifier {
  final pending = Completer<bool>();
  int calls = 0;

  @override
  VaultSettings build() => const VaultSettings(enabled: true);

  @override
  Future<bool> setPinProtected({required bool value, String? pin}) {
    calls++;
    return pending.future;
  }
}

void main() {
  testWidgets('repeated PIN submits start only one save and allow retry', (
    tester,
  ) async {
    final settings = _Settings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultSettingsProvider.overrideWith(() => settings)],
        child: const MaterialApp(
          home: Scaffold(body: PinDialog(alreadySet: false)),
        ),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'secret123');
    await tester.enterText(fields.at(1), 'secret123');
    final submit = tester.widget<TextField>(fields.at(1)).onSubmitted!;
    submit('secret123');
    submit('secret123');
    await tester.pump();
    expect(settings.calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    settings.pending.complete(false);
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy PIN dialog blocks cancel, barrier, and back', (
    tester,
  ) async {
    final settings = _Settings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultSettingsProvider.overrideWith(() => settings)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PinDialog.show(context, alreadySet: false),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'secret123');
    await tester.enterText(fields.at(1), 'secret123');
    tester.widget<TextField>(fields.at(1)).onSubmitted!('secret123');
    await tester.pump();
    expect(settings.calls, 1);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    await tester.tapAt(const Offset(2, 2));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(PinDialog), findsOneWidget);
    settings.pending.complete(false);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
          .onPressed,
      isNotNull,
    );
  });
}
