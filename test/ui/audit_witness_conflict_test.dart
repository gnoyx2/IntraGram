import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/features/chat/audit/audit_bundle_exchange.dart';
import 'package:intragram/l10n/strings.dart';

import '../support/test_identities.dart';

void main() {
  testWidgets('offline witness reports valid conflicting batch roots', (
    tester,
  ) async {
    // 봉인 큐(Future 체인)는 만든 zone에서 돌아서 실제 비동기 안에서 만들어야 runAsync가 기다릴 수 있음
    final requesters = (await tester.runAsync(() async {
      final stores = [
        for (var i = 0; i < 2; i++)
          EvidenceStore()..bindSigner(testIdentity('a')),
      ];
      for (final (i, store) in stores.indexed) {
        await store.issue(
          AttestationDraft(
            kind: AttestationKind.burnTriggered,
            subjectId: 'message$i',
            commitment: sha256B64([i]),
            policy: 'burn/timer',
            outcome: 'triggered',
          ),
        );
        await store.seal();
      }
      return stores;
    }))!;
    final [first, second] = requesters;
    final witness = EvidenceStore()..bindSigner(testIdentity('b'));
    for (final store in [first, second, witness]) {
      addTearDown(store.close);
    }
    expect(first.batches.single.header.no, second.batches.single.header.no);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var copied = 0;
    messenger.setMockMethodCallHandler(
      const MethodChannel('intragram/privacy'),
      (call) async {
        if (call.method == 'copySensitive') copied++;
        return null;
      },
    );
    addTearDown(() async {
      await OsPrivacy.clearClipboard();
      messenger.setMockMethodCallHandler(
        const MethodChannel('intragram/privacy'),
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AuditBundleExchange(
          evidence: witness,
          identity: testIdentity('b'),
        ),
      ),
    );
    for (final store in [first, second]) {
      await tester.enterText(
        find.byType(TextField).at(1),
        exportAnchorBundle(store, store.batches.single),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final sign = find.text('Sign external root & copy receipt');
      await tester.scrollUntilVisible(
        sign,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.runAsync(() async {
        await tester.tap(sign);
        await pumpEventQueue(times: 30);
      });
      await tester.pumpAndSettle();
    }
    expect(copied, 2);
    expect(witness.witnessed.map((w) => w.conflict), [false, true]);
    expect(
      find.text(const S(AppLang.en).t('audit.witnessConflict')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
