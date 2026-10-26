import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/features/chat/audit/audit_entry_tile.dart';
import 'support/test_identities.dart';

AttestationDraft _draft(String id) => AttestationDraft(
  kind: AttestationKind.burnTriggered,
  subjectId: id,
  commitment: sha256B64([1, 2, 3]),
  policy: 'burn/timer',
  outcome: 'triggered',
);

void main() {
  test(
    'clear never reuses a batch number under the same requester key',
    () async {
      final requester = EvidenceStore()..bindSigner(testIdentity('a'));
      final witness = EvidenceStore()..bindSigner(testIdentity('b'));
      addTearDown(requester.close);
      addTearDown(witness.close);
      await requester.issue(_draft('first'));
      final first = (await requester.seal())!;
      expect(witness.witness(testPeerId('a'), first.header), isFalse);
      requester.clear();
      await requester.issue(_draft('second'));
      final second = (await requester.seal())!;
      expect(second.header.no, greaterThan(first.header.no));
      expect(witness.witness(testPeerId('a'), second.header), isFalse);
    },
  );

  testWidgets('verified audit tile resets when reused for a different event', (
    tester,
  ) async {
    final evidence = (await tester.runAsync(
      () async => EvidenceStore()..bindSigner(testIdentity('a')),
    ))!;
    addTearDown(evidence.close);
    await tester.runAsync(() async {
      await evidence.issue(_draft('first'));
      await evidence.issue(_draft('second'));
      await evidence.seal();
    });
    Future<void> show(EvidenceEntry entry) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AuditEntryTile(evidence: evidence, entry: entry),
          ),
        ),
      ),
    );
    await show(evidence.entries.first);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Verify signature & Merkle proof'));
      await pumpEventQueue(times: 30);
    });
    await tester.pumpAndSettle();
    expect(find.text('Signature and Merkle proof verified'), findsOneWidget);
    await show(evidence.entries.last);
    await tester.pumpAndSettle();
    expect(find.text('Signature and Merkle proof verified'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
