import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/org_auth.dart';

import 'support/test_identities.dart';

void main() {
  final holder = testIdentity('a');
  final verifier = testIdentity('b');
  // 자격 장부는 실제 현재 시각으로 만료를 봄: 고정 날짜로 발급하면 그 12시간 뒤부터 실패함
  final now = DateTime.now().toUtc();
  final binding = Uint8List.fromList(List.generate(32, (i) => i));

  Future<OrgCredential> credential() => issueDemoCredential(
    holder,
    org: 'Institute',
    dept: 'Research',
    role: 'Researcher',
    now: now,
  );

  Future<OrgCheck> check(
    OrgCredential c, {
    List<int>? session,
    bool dialled = true,
    String? holderId,
    String? verifierId,
    TrustBundle? bundle,
    DateTime? at,
    List<int>? pop,
  }) async {
    final signature =
        pop ??
        await holder.sign(
          orgPopBytes(
            credentialDigest: c.digest,
            policy: c.policy,
            sessionBinding: binding,
            holderDialled: true,
            holderPeerId: holder.peerId,
            verifierPeerId: verifier.peerId,
          ),
        );
    return (await verifyOrgPresentation(
      credential: c,
      pop: signature,
      bundle: bundle ?? await demoTrustBundle(),
      holderPeerId: holderId ?? holder.peerId,
      verifierPeerId: verifierId ?? verifier.peerId,
      sessionBinding: session ?? binding,
      holderDialled: dialled,
      now: at ?? now,
    )).check;
  }

  test('real issuer signature and holder PoP validate offline', () async {
    final c = await credential();
    expect(await c.issuerSigned(), isTrue);
    expect(await check(c), OrgCheck.verified);
    expect(OrgCredential.fromWire(c.toWire())!.digest, c.digest);
    expect(
      OrgCredential.fromWire({...c.toWire(), 'exp': c.issuedAtMs}),
      isNull,
    );
  });

  test('PoP cannot move to another session, holder or direction', () async {
    final c = await credential();
    expect(await check(c, session: Uint8List(32)), OrgCheck.invalidPop);
    expect(await check(c, dialled: false), OrgCheck.invalidPop);
    expect(await check(c, verifierId: holder.peerId), OrgCheck.invalidPop);
    expect(await check(c, holderId: verifier.peerId), OrgCheck.subjectMismatch);
    expect(await check(c, pop: Uint8List(64)), OrgCheck.invalidPop);
  });

  test(
    'issuer trust, signed contents, expiry, snapshot and revocation enforced',
    () async {
      final c = await credential();
      final trusted = await demoTrustBundle();
      expect(
        await check(
          c,
          bundle: TrustBundle(
            id: 'none',
            snapshot: trusted.snapshot,
            issuers: const [],
          ),
        ),
        OrgCheck.untrustedIssuer,
      );
      final tampered = OrgCredential.fromWire({
        ...c.toWire(),
        'role': 'Admin',
      })!;
      expect(await check(tampered), OrgCheck.invalidSignature);
      expect(
        await check(c, at: now.add(const Duration(days: 1))),
        OrgCheck.expired,
      );
      expect(
        await check(c, at: DateTime.fromMillisecondsSinceEpoch(c.expiresAtMs)),
        OrgCheck.expired,
      );
      expect(
        await check(c, at: now.subtract(const Duration(hours: 1))),
        OrgCheck.notYetValid,
      );
      expect(
        await check(
          c,
          bundle: TrustBundle(
            id: 'revoked',
            snapshot: trusted.snapshot,
            issuers: trusted.issuers,
            revoked: {c.id},
          ),
        ),
        OrgCheck.revoked,
      );
      expect(
        await check(
          c,
          bundle: TrustBundle(
            id: 'stale',
            snapshot: '2026-10-23',
            issuers: trusted.issuers,
          ),
        ),
        OrgCheck.snapshotMismatch,
      );
    },
  );

  test('credential and trust bundle expose only immutable snapshots', () async {
    final c = await credential();
    final bundle = await demoTrustBundle();
    expect(() => c.subjectKey[0] = 0, throwsUnsupportedError);
    expect(() => c.issuerKey[0] = 0, throwsUnsupportedError);
    expect(() => c.signature[0] = 0, throwsUnsupportedError);
    expect(() => bundle.issuers.clear(), throwsUnsupportedError);
    expect(() => bundle.revoked.add(c.id), throwsUnsupportedError);
    expect(() => bundle.issuers.single.key[0] = 0, throwsUnsupportedError);
    expect(
      () => bundle.issuers.single.policies.clear(),
      throwsUnsupportedError,
    );
    final book = OrgCredentialBook();
    final owner = Object(), replacement = Object();
    final status = OrgCredentialStatus(check: OrgCheck.verified, credential: c);
    book.record(holder.peerId, status, owner: owner);
    book.record(holder.peerId, status, owner: replacement);
    book.forget(holder.peerId, owner: owner);
    expect(book.statusOf(holder.peerId), same(status));
    book.close();
  });

  test(
    'credential holder is bound to the current ephemeral identity',
    () async {
      final book = OrgCredentialBook();
      book.activate(await credential());
      expect(book.holderFor(holder), isNotNull);
      expect(book.holderFor(verifier), isNull);
      final before = book.generation;
      book.clear();
      expect(book.generation, before + 1);
      expect(book.holder, isNull);
      book.close();
    },
  );
}
