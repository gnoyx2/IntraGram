import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/audit/content_commitment.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/features/chat/audit/audit_bundle_exchange.dart';
import 'package:intragram/features/chat/audit/audit_entry_tile.dart';
import 'package:intragram/features/chat/audit/transfer_evidence_badges.dart';
import 'package:intragram/features/chat/audit_proof_sheet.dart';

import '../support/test_identities.dart';

Future<EvidenceStore> _evidence() async {
  final evidence = EvidenceStore()..bindSigner(testIdentity('a'));
  await evidence.issue(
    AttestationDraft(
      kind: AttestationKind.deliveryCommitted,
      subjectId: 'transfer1',
      attemptId: 'attempt1',
      commitment: sha256B64([1, 2, 3]),
      policy: 'delivery/file-commit',
      outcome: 'committed',
    ),
    transferId: 'transfer1',
  );
  return evidence;
}

void main() {
  testWidgets(
    'audit UI seals and verifies a real salted Merkle proof; badges advance',
    (tester) async {
      final evidence = (await tester.runAsync(_evidence))!;
      addTearDown(evidence.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TransferEvidenceBadges(
                  evidence: evidence,
                  transferId: 'transfer1',
                ),
                Expanded(
                  child: AuditProofSheet(
                    evidence: evidence,
                    identity: testIdentity('a'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Receipt signature confirmed'), findsOneWidget);
      expect(find.text('Included in Merkle batch'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.text('Commit Merkle batch'));
        await pumpEventQueue(times: 30);
      });
      await tester.pumpAndSettle();
      expect(evidence.batches, hasLength(1));
      expect(find.text('Included in Merkle batch'), findsOneWidget);

      expect(
        find.text(
          'Merkle proof · random salt + sibling path',
          skipOffstage: false,
        ),
        findsNothing,
      );
      await tester.ensureVisible(find.byType(AuditEntryTile));
      await tester.tap(find.text('Delivery committed'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verify signature & Merkle proof'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Verify signature & Merkle proof'));
        await pumpEventQueue(times: 30);
      });
      await tester.pumpAndSettle();
      expect(find.text('Signature and Merkle proof verified'), findsOneWidget);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? copied;
      messenger.setMockMethodCallHandler(
        const MethodChannel('intragram/privacy'),
        (call) async {
          if (call.method == 'copySensitive') copied = call.arguments as String;
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
      await tester.ensureVisible(find.text('Copy individual proof bundle'));
      await tester.tap(find.text('Copy individual proof bundle'));
      await tester.pump();
      expect(copied, isNotNull);
      expect((jsonDecode(copied!) as Map)['entries'], hasLength(1));
      await OsPrivacy.clearClipboard();
      evidence.clear();
      await tester.pumpAndSettle();
      expect(
        find.text('No signed receipts yet. Receive a file or burn a message.'),
        findsOneWidget,
      );
      expect(find.text('Receipt signature confirmed'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline second device signs a bundle; requester pins and imports witness',
    (tester) async {
      final evidence = (await tester.runAsync(_evidence))!;
      final witness = EvidenceStore()..bindSigner(testIdentity('b'));
      addTearDown(evidence.close);
      addTearDown(witness.close);
      await tester.runAsync(evidence.seal);
      final bundle = exportAnchorBundle(evidence, evidence.batches.single);
      String? clipboard;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('intragram/privacy'),
        (call) async {
          if (call.method == 'copySensitive') {
            clipboard = call.arguments as String;
          }
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

      Future<void> open(EvidenceStore store, String id) => tester.pumpWidget(
        MaterialApp(
          home: AuditBundleExchange(
            key: ValueKey(id),
            evidence: store,
            identity: testIdentity(id),
          ),
        ),
      );
      Future<void> tap(String text) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text(text));
          await pumpEventQueue(times: 30);
        });
        await tester.pumpAndSettle();
      }

      await open(witness, 'b');
      await tester.enterText(find.byType(TextField).at(1), bundle);
      await tap('Verify audit bundle');
      expect(
        find.text(
          'Bundle signatures and proofs verified · external witness unconfirmed',
        ),
        findsOneWidget,
      );
      await tap('Sign external root & copy receipt');
      expect(clipboard, isNotNull);
      final receipt = AnchorReceipt.fromWire(jsonDecode(clipboard!))!;
      expect(await tester.runAsync(receipt.verify), isTrue);

      await open(evidence, 'a');
      await tester.enterText(find.byType(TextField).first, testPeerId('c'));
      await tester.enterText(find.byType(TextField).at(1), clipboard!);
      await tap('Verify & attach witness receipt');
      expect(evidence.batches.single.anchor, isNull);
      expect(find.text('Verification failed'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, testPeerId('b'));
      await tap('Verify & attach witness receipt');
      expect(evidence.batches.single.anchor, isNotNull);
      expect(find.text('External anchor verified'), findsOneWidget);
      final verdict = await tester.runAsync(
        () => verifyAnchorBundle(
          exportAnchorBundle(evidence, evidence.batches.single),
          expectedWitnessPeerId: testPeerId('b'),
        ),
      );
      expect(verdict!.ok, isTrue);
      expect(verdict.anchored, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
