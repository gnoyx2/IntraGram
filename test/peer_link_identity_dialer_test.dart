import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_auth.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 앱 피어 링크의 신원 증명(프로토콜 v7): 다이얼러 쪽: 리스너가 hello에 실은 서명이 이번 세션의 내 커밋·
// 리스너 임시키·양쪽 신원키에 묶여 있어야 함. 증명되기 전엔 임시키를 공개하지도 자기 증명을 보내지도 않고 링크를 닫음
void main() {
  late InMemoryStore store;
  late PeerLink link;
  late ScriptedPeer peer;
  var secured = 0;

  // 진짜 다이얼러 링크(A) 하나와 그 반대편 스크립트 리스너를 엶: A의 hello가 이미 나간 상태
  Future<void> open({
    AppIdentity? dialer,
    AppIdentity? listener,
    String? expectedPeerId,
  }) async {
    final wire = StreamChannelController<dynamic>();
    final openStore = store = InMemoryStore()
      ..upsertConversation(conv('cA', 'bob'));
    secured = 0;
    final openLink = link = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: openStore,
      identity: dialer ?? testIdentity('a', alias: 'alice', platform: 'test'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
      expectedPeerId: expectedPeerId,
    );
    openLink.onSecure = () => secured++;
    peer = await ScriptedPeer.create(
      listener ?? testIdentity('b', alias: 'listener'),
      wire.foreign,
    );
    addTearDown(() async {
      await openLink.close();
      openStore.dispose();
    });
    await openLink.start();
    await pumpEventQueue(times: 30);
  }

  Future<void> expectRefused() async {
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);
    expect(link.isSecure, isFalse);
    expect(secured, 0);
    expect(
      peer.frames.where((f) => f['t'] == 'auth'),
      isEmpty,
      reason: 'no proof is sent to a listener that did not prove itself',
    );
    expect(store.conversation('cA'), isNotNull, reason: 'the dial is ours');
  }

  test('the dialer hello commits to its key without revealing it', () async {
    await open();
    final hello = peer.linkHello;
    expect(hello['peerId'], testPeerId('a'));
    expect(hello['idk'], base64.encode(testIdentity('a').publicKey!));
    expect(hello.containsKey('sig'), isFalse);
    expect(hello.containsKey('pub'), isFalse, reason: 'no key before reveal');
    expect(peer.linkCommitment, hasLength(32));
  });

  test('a listener that proves itself gets the dialer proof back', () async {
    await open();
    peer.sendHello(signature: await peer.proof(asDialer: false));
    await pumpEventQueue(times: 60);

    expect(link.remotePeerId, testPeerId('b'));
    expect(link.isSecure, isTrue);
    expect(secured, 1);
    expect(
      ephemeralCommitment(
        ephemeral: peer.linkRevealed,
        identityKey: peer.linkKey,
      ),
      peer.linkCommitment,
      reason: 'the revealed key opens the commitment',
    );
    expect(
      await verifyAuth(
        transcript: dialerTranscript(
          dialerEphemeral: peer.linkRevealed,
          listenerEphemeral: peer.session.publicKey,
          dialerKey: peer.linkKey,
          listenerKey: peer.key,
        ),
        signature: base64.decode(peer.linkAuth['sig'] as String),
        signerKey: peer.linkKey,
      ),
      isTrue,
    );
    await peer.completeHandshake(asDialer: false);
    expect(link.sasDigits, peer.session.sasDigits);
  });

  group('a listener that cannot prove itself is refused', () {
    test('without any signature', () async {
      await open();
      peer.sendHello();
      await expectRefused();
    });

    test('with a signature from another key', () async {
      await open();
      // c가 b의 peerId·키를 주장하며 자기 키로 서명함
      peer.sendHello(
        signature: await peer.proof(asDialer: false, signer: testIdentity('c')),
      );
      await expectRefused();
    });

    test('with a signature over another dialer commitment (replay)', () async {
      await open();
      peer.sendHello(
        signature: await peer.proof(
          asDialer: false,
          dialerCommitment: List<int>.filled(32, 3),
        ),
      );
      await expectRefused();
    });

    test('with a signature that names another dialer identity', () async {
      await open();
      peer.sendHello(
        signature: await peer.proof(
          asDialer: false,
          peerKey: testIdentity('c').publicKey,
        ),
      );
      await expectRefused();
    });

    test('with a dialer-role signature', () async {
      await open();
      peer.sendHello(
        signature: await peer.proof(asDialer: false, dialerRole: true),
      );
      await expectRefused();
    });

    test('whose peerId is not the hash of its key', () async {
      await open();
      peer.sendHello(
        peerId: testPeerId('c'),
        signature: await peer.proof(asDialer: false),
      );
      await expectRefused();
    });
  });

  test('the expected peerId is checked against the proven one', () async {
    await open(expectedPeerId: testPeerId('c')); // b가 아니라 c를 기대함
    peer.sendHello(signature: await peer.proof(asDialer: false));
    await expectRefused();
  });

  test('the expected peerId passes when the peer proves it', () async {
    await open(expectedPeerId: testPeerId('b'));
    peer.sendHello(signature: await peer.proof(asDialer: false));
    await pumpEventQueue(times: 60);
    expect(link.remotePeerId, testPeerId('b'));
  });

  test('an auth frame sent to a dialer closes the link', () async {
    await open();
    peer.sendAuth(List<int>.filled(64, 1));
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue);
  });

  test('an identity without a signing key cannot dial', () async {
    await open(
      dialer: AppIdentity(peerId: 'a' * 32, alias: 'alice', platform: 'test'),
    );
    expect(link.isClosed, isTrue);
    expect(peer.frames, isEmpty, reason: 'no hello was sent');
  });
}
