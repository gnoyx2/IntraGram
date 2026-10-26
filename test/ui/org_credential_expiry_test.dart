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
  testWidgets('visible organization badge expires while SAS stays verified', (
    tester,
  ) async {
    final identity = testIdentity('a');
    final remote = testIdentity('b');
    final status = (await tester.runAsync(() async {
      final credential = await issueDemoCredential(
        remote,
        org: 'Institute',
        dept: 'Security',
        role: 'Researcher',
        validFor: const Duration(minutes: 1),
      );
      final binding = List<int>.filled(32, 7);
      return verifyOrgPresentation(
        credential: credential,
        pop: await remote.sign(
          orgPopBytes(
            credentialDigest: credential.digest,
            policy: credential.policy,
            sessionBinding: binding,
            holderDialled: false,
            holderPeerId: remote.peerId,
            verifierPeerId: identity.peerId,
          ),
        ),
        bundle: await demoTrustBundle(),
        holderPeerId: remote.peerId,
        verifierPeerId: identity.peerId,
        sessionBinding: binding,
        holderDialled: false,
      );
    }))!;
    expect(status.verified, isTrue);
    final conversation = conv(
      'c1',
      'peer',
    ).copyWith(peerId: remote.peerId, localVerified: true, peerVerified: true);
    final store = InMemoryStore()..upsertConversation(conversation);
    addTearDown(store.dispose);
    store.orgCredentials.record(remote.peerId, status, owner: Object());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(store),
          appIdentityProvider.overrideWithValue(identity),
        ],
        child: MaterialApp(
          home: Scaffold(body: OrgCredentialButton(conversation: conversation)),
        ),
      ),
    );
    expect(find.byIcon(Icons.domain_verification), findsOneWidget);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.domain_verification), findsNothing);
    expect(find.byIcon(Icons.business_outlined), findsOneWidget);
    expect(
      store.orgCredentials.statusOf(remote.peerId)?.check,
      OrgCheck.expired,
    );
    expect(store.conversation('c1')!.verified, isTrue);
    await tester.tap(find.byIcon(Icons.business_outlined));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Organization credential expired'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
