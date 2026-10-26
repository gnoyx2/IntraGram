import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/audit/attestation.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/room_integrity/author_event.dart';

import 'support/handshake_pair.dart';
import 'support/test_identities.dart';

String _escaped(String encoded) => encoded.codeUnits
    .map((unit) => '%${unit.toRadixString(16).padLeft(2, '0')}')
    .join();

void main() {
  test('fixed byte fields reject oversized encoded representations', () {
    for (final length in [16, 32, 64]) {
      final encoded = base64.encode(Uint8List(length));
      final escaped = _escaped(encoded);
      // 정규화된 형태는 바이트 수가 맞더라도 원본 전송(wire) 형태가 인코딩 길이 제한을 초과함
      expect(base64.decode(base64.normalize(escaped)), hasLength(length));
      expect(wireBytes(escaped, length: length), isNull);
      expect(wireBytes(encoded, length: length), hasLength(length));
      for (final size in [4096, 1024 * 1024, 4 * 1024 * 1024]) {
        expect(wireBytes('A' * size, length: length), isNull);
      }
    }
  });

  test('authorSig and nested sg enforce the same encoded size limit', () async {
    final identity = testIdentity('a');
    final author = await RoomAuthorEvent.sign(
      identity,
      roomId: 'room',
      hostPeerId: identity.peerId,
      counter: 1,
      previousHash: base64.encode(Uint8List(32)),
      payload: {'id': 'message', 'text': 'yes'},
    );
    final signed = await SignedAttestation.sign(
      identity,
      AttestationDraft(
        kind: AttestationKind.burnTriggered,
        subjectId: 'message',
        commitment: base64.encode(Uint8List(32)),
        policy: 'burn/manual',
        outcome: 'triggered',
      ),
    );
    final credential = await issueDemoCredential(
      identity,
      org: 'Institute',
      dept: 'Security',
      role: 'Researcher',
    );
    final badSignatures = [
      _escaped(author.toWire()['authorSig'] as String),
      'A' * 4096,
      'A' * (1024 * 1024),
    ];
    for (final oversized in badSignatures) {
      expect(
        RoomAuthorEvent.fromWire({
          ...author.toWire(),
          'authorSig': oversized,
        }, hostPeerId: identity.peerId),
        isNull,
      );
      expect(
        SignedAttestation.fromWire({...signed.toWire(), 'sg': oversized}),
        isNull,
      );
      expect(
        OrgCredential.fromWire({...credential.toWire(), 'sg': oversized}),
        isNull,
      );
    }
  });

  test('oversized PoP is refused on a live authenticated link', () async {
    final pair = await connectedPair();
    addTearDown(() async {
      await pair.linkA.close();
      await pair.linkB.close();
      pair.storeA.dispose();
      pair.storeB.dispose();
    });
    final credential = await issueDemoCredential(
      pair.linkA.identity,
      org: 'Institute',
      dept: 'Security',
      role: 'Researcher',
    );
    for (final oversized in [
      _escaped(base64.encode(Uint8List(64))),
      'A' * 4096,
      'A' * (1024 * 1024),
    ]) {
      await pair.linkA.sendRawInner({
        'k': 'org_cred',
        'credential': credential.toWire(),
        'credentialDigest': credential.digest,
        'policy': credential.policy,
        'pop': oversized,
      });
      await pumpEventQueue(times: 60);
      expect(
        pair.storeB.orgCredentials.statusOf(pair.linkA.identity.peerId),
        isNull,
      );
    }
    await pair.linkA.sendText('still usable', ttlSeconds: 0);
    await pumpEventQueue(times: 60);
    expect(chat(pair.storeB, 'cB').single.text, 'still usable');
    expect(pair.linkB.isClosed, isFalse);
  });
}
