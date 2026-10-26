import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/chat/widgets/org_credential_badge.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/store/in_memory_store.dart';

import '../support/handshake_pair.dart';
import '../support/test_identities.dart';

void main() {
  testWidgets('organization dialog issues a real signed session credential', (
    tester,
  ) async {
    final store = InMemoryStore();
    final identity = testIdentity('a');
    final remote = testIdentity('b');
    final status = await tester.runAsync(() async {
      final credential = await issueDemoCredential(
        remote,
        org: 'Verified Institute',
        dept: 'Engineering',
        role: 'Reviewer',
      );
      final binding = List<int>.filled(32, 7);
      final pop = await remote.sign(
        orgPopBytes(
          credentialDigest: credential.digest,
          policy: credential.policy,
          sessionBinding: binding,
          holderDialled: false,
          holderPeerId: remote.peerId,
          verifierPeerId: identity.peerId,
        ),
      );
      return verifyOrgPresentation(
        credential: credential,
        pop: pop,
        bundle: await demoTrustBundle(),
        holderPeerId: remote.peerId,
        verifierPeerId: identity.peerId,
        sessionBinding: binding,
        holderDialled: false,
      );
    });
    final owner = Object();
    store.orgCredentials.record(remote.peerId, status!, owner: owner);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          appIdentityProvider.overrideWithValue(identity),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OrgCredentialButton(
              conversation: conv('c', 'peer').copyWith(peerId: remote.peerId),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.domain_verification));
    await tester.pumpAndSettle();
    expect(find.text('Offline organization credential'), findsOneWidget);
    expect(find.textContaining('public demo key'), findsOneWidget);
    expect(find.textContaining('Engineering · $kDemoPolicy'), findsOneWidget);
    expect(find.textContaining('Expires:'), findsOneWidget);
    store.orgCredentials.record(
      remote.peerId,
      OrgCredentialStatus(
        check: OrgCheck.invalidSignature,
        credential: status.credential,
      ),
      owner: owner,
    );
    await tester.pump();
    expect(find.textContaining('Engineering'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Issue and activate demo credential'));
      await pumpEventQueue(times: 80);
    });
    await tester.pumpAndSettle();
    expect(store.orgCredentials.holder?.subjectKey, identity.publicKey);
    final signed = await tester.runAsync(
      () => store.orgCredentials.holder!.issuerSigned(),
    );
    expect(signed, isTrue);
    expect(find.textContaining('Demo Research Institute'), findsOneWidget);
    expect(find.text('Stop presenting'), findsOneWidget);
    await tester.tap(find.text('Stop presenting'));
    await tester.pumpAndSettle();
    expect(store.orgCredentials.holder, isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
}
