import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/audit/evidence_store.dart';
import 'package:intragram/audit/merkle.dart';

import 'support/test_identities.dart';

final _draft = AttestationDraft(
  kind: AttestationKind.deliveryCommitted,
  subjectId: 'file',
  attemptId: 'attempt',
  commitment: 'n4bQgYhMfWWaL+qgxVrQFaO/TxsrC4Is0V1sFbDwCgg=',
  policy: 'delivery/file-commit',
  outcome: 'committed',
);

Future<EvidenceStore> _batched() async {
  final store = EvidenceStore()..bindSigner(testIdentity('a'));
  await store.issue(_draft);
  await store.issue(_draft);
  await store.seal();
  return store;
}

void main() {
  test('draft copies and freezes its counterpart key before signing', () async {
    final key = Uint8List.fromList(testIdentity('a').publicKey!);
    final draft = AttestationDraft(
      kind: _draft.kind,
      subjectId: _draft.subjectId,
      commitment: _draft.commitment,
      policy: _draft.policy,
      outcome: _draft.outcome,
      counterpartId: testPeerId('a'),
      counterpartKey: key,
    );
    key[0] ^= 1;
    expect(draft.counterpartKey, testIdentity('a').publicKey);
    expect(() => draft.counterpartKey![0] ^= 1, throwsUnsupportedError);
    final signed = await SignedAttestation.sign(testIdentity('b'), draft);
    expect(await signed.verify(), isTrue);
  });

  test('a pasted bundle with more entries than a batch can hold is refused '
      'before any signature check', () async {
    final store = await _batched();
    final bundle =
        jsonDecode(exportAnchorBundle(store, store.batches.single))
            as Map<String, dynamic>;
    final entry = (bundle['entries'] as List).first;
    bundle['entries'] = List.filled(EvidenceStore.maxEntries + 1, entry);
    final verdict = await verifyAnchorBundle(jsonEncode(bundle));
    expect(verdict.ok, isFalse);
    expect(verdict.error, 'entries');
  });

  test('the full sender key is signed and must match its peerId', () async {
    final signed = await SignedAttestation.sign(
      testIdentity('b'),
      AttestationDraft(
        kind: _draft.kind,
        subjectId: _draft.subjectId,
        commitment: _draft.commitment,
        policy: _draft.policy,
        outcome: _draft.outcome,
        counterpartId: testPeerId('a'),
        counterpartKey: testIdentity('a').publicKey,
      ),
    );
    expect(await signed.verify(), isTrue);
    expect(() => signed.counterpartKey![0] ^= 1, throwsUnsupportedError);
    final tampered = {
      ...signed.toWire(),
      'ck': base64.encode(testIdentity('c').publicKey!),
    };
    expect(SignedAttestation.fromWire(tampered), isNull);
    tampered['cp'] = testPeerId('c');
    expect(await SignedAttestation.fromWire(tampered)!.verify(), isFalse);
  });

  test('a Merkle proof cannot use arbitrary bytes as a leaf or root', () {
    expect(
      verifyMerkleProof(leaf: [1], index: 0, leafCount: 1, path: [], root: [1]),
      isFalse,
    );
    final leaf = merkleLeaf([1], [2]);
    expect(
      verifyMerkleProof(
        leaf: leaf,
        index: 0,
        leafCount: 2,
        path: [
          [1],
        ],
        root: merkleNode(leaf, [1]),
      ),
      isFalse,
    );
  });

  test(
    'signed evidence, salts and batch leaves are immutable copies',
    () async {
      final store = await _batched();
      final entry = store.entries.first;
      final batch = store.batches.single;
      for (final buffer in [
        entry.attestation.signerKey,
        entry.attestation.signature,
        entry.leafSalt,
        batch.header.root,
        batch.header.signerKey,
        batch.header.signature,
        batch.leaves.first,
      ]) {
        expect(() => buffer[0] ^= 1, throwsUnsupportedError);
      }
      final mutable = Uint8List.fromList(batch.header.root);
      final copy = BatchHeader(
        no: batch.header.no,
        leafCount: batch.header.leafCount,
        root: mutable,
        sealedAtMs: batch.header.sealedAtMs,
        signerKey: batch.header.signerKey,
        signature: batch.header.signature,
      );
      mutable[0] ^= 1;
      expect(await copy.verify(), isTrue);
      expect(await entry.attestation.verify(), isTrue);
    },
  );

  test(
    'duplicating a proof cannot pretend to prove distinct entries',
    () async {
      final store = await _batched();
      final raw = jsonDecode(exportAnchorBundle(store, store.batches.single));
      raw['entries'][1] = raw['entries'][0];
      final verdict = await verifyAnchorBundle(jsonEncode(raw));
      expect(verdict.ok, isFalse);
      expect(verdict.validEntries, 1);
    },
  );

  test(
    'an anchor signature requires an independently pinned external witness',
    () async {
      final store = await _batched();
      final batch = store.batches.single;
      final receipt = await AnchorReceipt.witness(
        testIdentity('b'),
        batch.header,
      );
      expect(receipt.signature, isNotEmpty);
      expect(() => receipt.signature[0] ^= 1, throwsUnsupportedError);
      expect(
        await store.attachAnchor(receipt, witnessPeerId: testPeerId('b')),
        isTrue,
      );
      final bundle = exportAnchorBundle(store, store.batches.single);
      final unpinned = await verifyAnchorBundle(bundle);
      expect(unpinned.ok, isTrue);
      expect(unpinned.anchorSigned, isTrue);
      expect(unpinned.anchored, isNull);
      expect(unpinned.witnessPeerId, testPeerId('b'));
      final pinned = await verifyAnchorBundle(
        bundle,
        expectedWitnessPeerId: testPeerId('b'),
      );
      expect(pinned.anchored, isTrue);
      final wrong = await verifyAnchorBundle(
        bundle,
        expectedWitnessPeerId: testPeerId('c'),
      );
      expect(wrong.anchored, isFalse);
      expect(wrong.ok, isFalse);
    },
  );

  test(
    'a requester cannot count its own signature as an external anchor',
    () async {
      final store = await _batched();
      final header = store.batches.single.header;
      await expectLater(
        AnchorReceipt.witness(testIdentity('a'), header),
        throwsArgumentError,
      );
      final raw = (await AnchorReceipt.witness(
        testIdentity('b'),
        header,
      )).toWire();
      raw['wk'] = base64.encode(testIdentity('a').publicKey!);
      final unsigned = AnchorReceipt.fromWire(raw)!;
      raw['sg'] = base64.encode(
        await testIdentity('a').sign(unsigned.signedBytes),
      );
      final selfSigned = AnchorReceipt.fromWire(raw)!;
      expect(await selfSigned.verify(), isFalse);
      expect(
        await store.attachAnchor(selfSigned, witnessPeerId: testPeerId('a')),
        isFalse,
      );
    },
  );

  test(
    'a queued seal and completed verification cannot revive wiped evidence',
    () async {
      final store = await _batched();
      final signed = store.entries.first.attestation;
      final generation = store.generation;
      final lateSeal = store.seal();
      store.clear();
      await store.issue(_draft);
      expect(await lateSeal, isNull);
      store.record(signed, verified: true, sinceGeneration: generation);
      expect(store.entries, hasLength(1));
      expect(store.entries.single.attestation.eventId, isNot(signed.eventId));
      expect(store.batches, isEmpty);
    },
  );
}
