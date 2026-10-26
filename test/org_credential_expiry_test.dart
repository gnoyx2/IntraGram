import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/org_auth.dart';

import 'support/test_identities.dart';

void main() {
  test(
    'one expiry timer downgrades peers and stops local presentation',
    () async {
      final identity = testIdentity('a');
      final credential = await issueDemoCredential(
        identity,
        org: 'Institute',
        dept: 'Security',
        role: 'Researcher',
        validFor: const Duration(minutes: 1),
      );
      fakeAsync((async) {
        final book = OrgCredentialBook();
        var notifications = 0;
        book.addListener(() => notifications++);
        book.activate(credential);
        book.record(
          identity.peerId,
          OrgCredentialStatus(
            check: OrgCheck.verified,
            credential: credential,
            issuerName: 'Institute issuer',
            demo: true,
          ),
          owner: Object(),
        );
        expect(async.nonPeriodicTimerCount, 1);
        expect(book.statusOf(identity.peerId)?.verified, isTrue);
        async.elapse(const Duration(minutes: 1));
        final expired = book.statusOf(identity.peerId)!;
        expect(expired.check, OrgCheck.expired);
        expect(expired.issuerName, 'Institute issuer');
        expect(expired.demo, isTrue);
        expect(book.holderFor(identity), isNull);
        expect(notifications, 3);
        expect(async.nonPeriodicTimerCount, 0);
        book.activate(credential);
        expect(async.nonPeriodicTimerCount, 1);
        book.clear();
        expect(async.nonPeriodicTimerCount, 0);
        book.close();
      });
    },
  );

  test('session binding is immutable and disappears on destroy', () async {
    final engine = CryptoEngine();
    final a = await engine.createSession();
    final b = await engine.createSession();
    await a.completeHandshake(b.publicKeyBase64);
    await b.completeHandshake(a.publicKeyBase64);
    expect(a.sessionBinding, b.sessionBinding);
    expect(() => a.sessionBinding![0] ^= 1, throwsUnsupportedError);
    a.destroy();
    b.destroy();
    expect(a.sessionBinding, isNull);
  });
}
