import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/audit/merkle.dart';

import 'support/test_identities.dart';

// 서명 증적·Salted Merkle 배치·감사 번들·증인 앵커가 진짜 Ed25519/SHA-256으로 맞물리는지,
// 한 바이트만 바꿔도 검증이 깨지는지 봄

final _draft = AttestationDraft(
  kind: AttestationKind.deliveryCommitted,
  subjectId: 't1',
  attemptId: 'a1',
  counterpartId: 'ab12ab12ab12ab12ab12ab12ab12ab12',
  commitment: 'n4bQgYhMfWWaL+qgxVrQFaO/TxsrC4Is0V1sFbDwCgg=',
  policy: 'delivery/file-commit',
  outcome: 'committed',
);

EvidenceStore _store(String tag) =>
    EvidenceStore()..bindSigner(testIdentity(tag));

void main() {
  group('signed attestation', () {
    test('round-trips through the wire and verifies', () async {
      final signed = await SignedAttestation.sign(testIdentity('b'), _draft);
      final back = SignedAttestation.fromWire(
        jsonDecode(jsonEncode(signed.toWire())),
      )!;
      expect(await back.verify(), isTrue);
      expect(back.signerPeerId, testPeerId('b'));
      expect(back.attemptId, 'a1');
    });

    test('any edited field breaks the signature', () async {
      final wire = (await SignedAttestation.sign(
        testIdentity('b'),
        _draft,
      )).toWire();
      for (final edit in <String, Object>{
        'a': 'a2',
        's': 't2',
        'o': 'failed',
        'c': base64.encode(List<int>.filled(32, 1)),
        'pk': base64.encode(testIdentity('c').publicKey!),
      }.entries) {
        final forged = SignedAttestation.fromWire({
          ...wire,
          edit.key: edit.value,
        });
        expect(await forged!.verify(), isFalse, reason: edit.key);
      }
    });

    test('malformed fields are refused instead of defaulted', () async {
      final wire = (await SignedAttestation.sign(
        testIdentity('b'),
        _draft,
      )).toWire();
      for (final bad in <String, Object?>{
        'domain': 'intragram/attestation/v2',
        'k': 'minted',
        'pk': 'AAAA',
        'p': 'Delivery Commit',
        't': 1.5,
        'sg': null,
      }.entries) {
        final raw = {...wire}..[bad.key] = bad.value;
        expect(SignedAttestation.fromWire(raw), isNull, reason: bad.key);
      }
    });

    test('a small-order signer key never verifies', () async {
      final wire = (await SignedAttestation.sign(
        testIdentity('b'),
        _draft,
      )).toWire();
      final identityPoint = Uint8List(32)..[0] = 1;
      final forged = SignedAttestation.fromWire({
        ...wire,
        'pk': base64.encode(identityPoint),
      })!;
      expect(await forged.verify(), isFalse);
    });
  });

  test(
    'every leaf of every tree size proves into its root, and only there',
    () {
      for (var n = 1; n <= 9; n++) {
        final leaves = [
          for (var i = 0; i < n; i++) merkleLeaf([i], utf8.encode('event $i')),
        ];
        final root = merkleRoot(leaves);
        for (var i = 0; i < n; i++) {
          final path = merkleProof(leaves, i);
          expect(
            verifyMerkleProof(
              leaf: leaves[i],
              index: i,
              leafCount: n,
              path: path,
              root: root,
            ),
            isTrue,
            reason: '$i of $n',
          );
          if (n > 1) {
            expect(
              verifyMerkleProof(
                leaf: leaves[i],
                index: (i + 1) % n,
                leafCount: n,
                path: path,
                root: root,
              ),
              isFalse,
            );
          }
        }
      }
      // 같은 내용이라도 salt가 다르면 다른 잎: 증명에 딸린 형제 해시로 다른 사건을 사전 대입 못 함
      expect(merkleLeaf([1], [7]), isNot(merkleLeaf([2], [7])));
    },
  );

  group('evidence batches', () {
    test('sealing commits every pending entry under one signed root', () async {
      final store = _store('a');
      for (var i = 0; i < 3; i++) {
        await store.issue(_draft, conversationId: 'c1', transferId: 't$i');
      }
      final batch = (await store.seal())!;
      expect(batch.header.leafCount, 3);
      expect(await batch.header.verify(), isTrue);
      expect(store.unbatched, isEmpty);
      for (final entry in store.entries) {
        expect(
          verifyMerkleProof(
            leaf: entry.leaf,
            index: entry.batchIndex!,
            leafCount: 3,
            path: store.proofFor(entry)!,
            root: batch.header.root,
          ),
          isTrue,
        );
      }
      expect(await store.seal(), isNull, reason: 'nothing left to seal');
    });

    test(
      'a bundle verifies, a one-byte edit does not, a subset still does',
      () async {
        final store = _store('a');
        await store.issue(_draft);
        final kept = (await store.issue(_draft))!;
        final batch = (await store.seal())!;
        final full = exportAnchorBundle(store, batch);
        final verdict = await verifyAnchorBundle(full);
        expect(verdict.ok, isTrue);
        expect(verdict.validEntries, 2);
        expect(verdict.anchored, isNull);

        final tampered = full.replaceFirst('"committed"', '"committex"');
        expect((await verifyAnchorBundle(tampered)).ok, isFalse);
        expect((await verifyAnchorBundle('{not json')).error, 'json');

        final one = exportAnchorBundle(store, batch, only: {kept.eventId});
        final partial = await verifyAnchorBundle(one);
        expect(partial.ok, isTrue);
        expect(partial.entryCount, 1);
      },
    );

    test('a witness anchor attaches only from the linked witness', () async {
      final store = _store('a');
      await store.issue(_draft);
      final batch = (await store.seal())!;
      final receipt = await AnchorReceipt.witness(
        testIdentity('b'),
        batch.header,
      );
      expect(
        await store.attachAnchor(receipt, witnessPeerId: testPeerId('c')),
        isFalse,
      );
      expect(
        await store.attachAnchor(receipt, witnessPeerId: testPeerId('b')),
        isTrue,
      );
      final anchored = store.batch(batch.header.no)!;
      final verdict = await verifyAnchorBundle(
        exportAnchorBundle(store, anchored),
        expectedWitnessPeerId: testPeerId('b'),
      );
      expect(verdict.anchored, isTrue);
      expect(verdict.ok, isTrue);
    });

    test('a witness sees a second root for the same batch as a conflict', () {
      final witness = _store('b');
      BatchHeader header(int fill) => BatchHeader(
        no: 1,
        leafCount: 1,
        root: Uint8List(32)..fillRange(0, 32, fill),
        sealedAtMs: 1,
        signerKey: testIdentity('a').publicKey!,
        signature: Uint8List(64),
      );
      expect(witness.witness(testPeerId('a'), header(1)), isFalse);
      expect(witness.witness(testPeerId('a'), header(1)), isFalse);
      expect(witness.witness(testPeerId('a'), header(2)), isTrue);
    });

    test('a signature that finishes after clear is dropped', () async {
      final store = _store('a');
      final late = store.issue(_draft);
      store.clear();
      expect(await late, isNull);
      expect(store.entries, isEmpty);
    });
  });
}
