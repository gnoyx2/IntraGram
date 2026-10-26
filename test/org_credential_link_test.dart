import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/peer_link.dart';

import 'support/handshake_pair.dart';

void main() {
  test(
    'post-handshake activation verifies organization separately from SAS',
    () async {
      final p = await connectedPair();
      addTearDown(() async {
        await p.linkA.close();
        await p.linkB.close();
        p.storeA.dispose();
        p.storeB.dispose();
      });
      p.storeB.updateConversation(
        'cB',
        (c) => c.copyWith(localVerified: true, peerVerified: false),
      );
      final sas = p.storeB.conversation('cB')!.sas;
      expect(p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId), isNull);
      p.storeA.orgCredentials.activate(
        await issueDemoCredential(
          p.linkA.identity,
          org: 'Institute',
          dept: 'Security',
          role: 'Researcher',
        ),
      );
      await pumpEventQueue(times: 120);
      final status = p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId);
      expect(status?.check, OrgCheck.verified);
      expect(status?.demo, isTrue);
      final c = p.storeB.conversation('cB')!;
      expect(c.sas, sas);
      expect(c.localVerified, isTrue);
      expect(c.peerVerified, isFalse);
      expect(c.verified, isFalse);
      await p.linkA.sendText('ordinary chat', ttlSeconds: 0);
      await pumpEventQueue(times: 60);
      expect(chat(p.storeB, 'cB').single.text, 'ordinary chat');
      await p.linkB.close();
      expect(p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId), isNull);
    },
  );

  test(
    'a credential replaced during signing still presents the latest issue',
    () async {
      final p = await connectedPair();
      addTearDown(() async {
        await p.linkA.close();
        await p.linkB.close();
        p.storeA.dispose();
        p.storeB.dispose();
      });
      Future<OrgCredential> issue(String role) => issueDemoCredential(
        p.linkA.identity,
        org: 'Institute',
        dept: 'Security',
        role: role,
      );
      final first = await issue('Researcher');
      final latest = await issue('Reviewer');
      p.storeA.orgCredentials.activate(first);
      p.storeA.orgCredentials.activate(latest);
      await pumpEventQueue(times: 160);
      final status = p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId);
      expect(status?.check, OrgCheck.verified);
      expect(status?.credential.digest, latest.digest);
      expect(status?.credential.role, 'Reviewer');
    },
  );

  test('stopping takes the badge down on the peer and many re-issues still '
      'end on the latest credential', () async {
    final p = await connectedPair();
    addTearDown(() async {
      await p.linkA.close();
      await p.linkB.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });
    final holder = p.linkA.identity.peerId;
    for (var i = 1; i <= 10; i++) {
      p.storeA.orgCredentials.activate(
        await issueDemoCredential(
          p.linkA.identity,
          org: 'Institute',
          dept: 'Security',
          role: 'Role $i',
        ),
      );
      await pumpEventQueue(times: 40);
    }
    await pumpEventQueue(times: 120);
    expect(
      p.storeB.orgCredentials.statusOf(holder)?.credential.role,
      'Role 10',
    );
    p.storeA.orgCredentials.deactivate();
    await pumpEventQueue(times: 80);
    expect(p.storeB.orgCredentials.statusOf(holder), isNull);
  });

  test(
    'panic clear prevents an in-flight credential verification restoring RAM state',
    () async {
      final p = await connectedPair();
      addTearDown(() async {
        await p.linkA.close();
        await p.linkB.close();
        p.storeA.dispose();
        p.storeB.dispose();
      });
      final trusted = await demoTrustBundle();
      final gate = Completer<TrustBundle>();
      var checking = false;
      p.storeB.orgCredentials.trustBundle = () {
        checking = true;
        return gate.future;
      };
      p.storeA.orgCredentials.activate(
        await issueDemoCredential(
          p.linkA.identity,
          org: 'Institute',
          dept: 'Security',
          role: 'Researcher',
        ),
      );
      await pumpEventQueue(times: 80);
      expect(checking, isTrue);
      await p.linkA.sendText(
        'chat while credential check waits',
        ttlSeconds: 0,
      );
      await pumpEventQueue(times: 60);
      expect(
        chat(p.storeB, 'cB').single.text,
        'chat while credential check waits',
      );
      p.storeB.secureWipe();
      gate.complete(trusted);
      await pumpEventQueue(times: 80);
      expect(p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId), isNull);
      expect(p.storeB.orgCredentials.holder, isNull);
    },
  );

  test(
    'a secure link left open after wipe cannot exchange new credentials',
    () async {
      final p = await connectedPair();
      addTearDown(() async {
        await p.linkA.close();
        await p.linkB.close();
        p.storeA.dispose();
        p.storeB.dispose();
      });
      final credentialA = await issueDemoCredential(
        p.linkA.identity,
        org: 'Institute',
        dept: 'Security',
        role: 'Researcher',
      );
      final credentialB = await issueDemoCredential(
        p.linkB.identity,
        org: 'Institute',
        dept: 'Security',
        role: 'Reviewer',
      );
      p.storeB.secureWipe();
      expect(
        p.linkB.isSecure,
        isTrue,
        reason: 'simulates a hung link shutdown',
      );
      p.storeA.orgCredentials.activate(credentialA);
      p.storeB.orgCredentials.activate(credentialB);
      await pumpEventQueue(times: 120);
      expect(p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId), isNull);
      expect(p.storeA.orgCredentials.statusOf(p.linkB.identity.peerId), isNull);
    },
  );

  test(
    'deleting a conversation during credential verification drops the result',
    () async {
      final p = await connectedPair();
      addTearDown(() async {
        await p.linkA.close();
        await p.linkB.close();
        p.storeA.dispose();
        p.storeB.dispose();
      });
      final trusted = await demoTrustBundle();
      final gate = Completer<TrustBundle>();
      var checking = false;
      p.storeB.orgCredentials.trustBundle = () {
        checking = true;
        return gate.future;
      };
      p.storeA.orgCredentials.activate(
        await issueDemoCredential(
          p.linkA.identity,
          org: 'Institute',
          dept: 'Security',
          role: 'Researcher',
        ),
      );
      await pumpEventQueue(times: 80);
      expect(checking, isTrue);
      p.storeB.wipeConversation('cB');
      gate.complete(trusted);
      await pumpEventQueue(times: 80);
      expect(p.storeB.orgCredentials.statusOf(p.linkA.identity.peerId), isNull);
    },
  );
}
