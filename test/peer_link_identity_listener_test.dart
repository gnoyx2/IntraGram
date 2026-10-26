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

// 앱 피어 링크의 신원 증명(프로토콜 v7): 리스너 쪽: 다이얼러가 hello로 밝힌 peerId를 실제로 가진 쪽임이
// 증명되기 전엔 그 peerId를 링크·store·registry 어디에도 반영하지 않고, 위조된 증명은 링크를 닫음
// 다이얼러는 hello에 임시키 커밋만 싣고, 공개한 임시키가 커밋과 다르면 거절함
void main() {
  late InMemoryStore store;
  late PeerLink link;
  late ScriptedPeer peer;
  var identified = 0;
  var secured = 0;

  // 진짜 리스너 링크(B) 하나와 그 반대편 스크립트 다이얼러를 엶
  Future<void> open({AppIdentity? listener, AppIdentity? dialer}) async {
    final wire = StreamChannelController<dynamic>();
    final openStore = store = InMemoryStore()
      ..upsertConversation(conv('cB', 'peer'));
    identified = 0;
    secured = 0;
    final openLink = link = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: openStore,
      identity: listener ?? testIdentity('b', alias: 'host', platform: 'test'),
      crypto: await CryptoEngine().createSession(),
    );
    openLink
      ..onAppPeerIdentified = (() => identified++)
      ..onSecure = (() => secured++);
    peer = await ScriptedPeer.create(
      dialer ?? testIdentity('a', alias: 'dialer'),
      wire.local,
    );
    addTearDown(() async {
      await openLink.close();
      openStore.dispose();
    });
    await openLink.start();
  }

  // 다이얼러가 hello를 보내고 리스너의 답을 받은 뒤 키 합의까지 끝냄
  Future<void> hello({String? peerId, List<int>? claimedKey}) async {
    peer.sendDialerHello(peerId: peerId, claimedKey: claimedKey);
    await pumpEventQueue(times: 60);
    await peer.completeHandshake();
  }

  Future<void> expectRefused({bool placeholderWiped = true}) async {
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);
    expect(link.isSecure, isFalse);
    expect(identified + secured, 0, reason: 'nothing was reported upward');
    if (placeholderWiped) expect(store.conversation('cB'), isNull);
  }

  test('the dialer stays unknown until its proof arrives', () async {
    await open();
    await hello();

    final answer = peer.linkHello;
    expect(answer['idk'], base64.encode(testIdentity('b').publicKey!));
    expect(
      await verifyAuth(
        transcript: listenerTranscript(
          dialerCommitment: peer.commitment,
          listenerEphemeral: peer.linkEphemeral,
          dialerKey: peer.key,
          listenerKey: peer.linkKey,
        ),
        signature: base64.decode(answer['sig'] as String),
        signerKey: peer.linkKey,
      ),
      isTrue,
      reason: 'the listener proves itself over the dialer commitment',
    );
    expect(link.isClosed, isFalse);
    expect(link.remotePeerId, isNull);
    expect(link.isSecure, isFalse);
    expect(
      link.sasDigits,
      isNull,
      reason: 'no key agreement before the dialer reveals its key',
    );
    expect(
      link.isPendingHandshake,
      isTrue,
      reason: 'still counts against the unauthenticated-link cap',
    );
    expect(identified + secured, 0);
    expect(store.conversation('cB')!.secure, isFalse);
    expect(store.conversation('cB')!.peerAlias, 'peer', reason: 'not applied');
  });

  test('a valid proof identifies the dialer and secures the link', () async {
    await open();
    await hello();
    peer.sendAuth(await peer.proof(asDialer: true));
    await pumpEventQueue(times: 60);

    expect(link.remotePeerId, testPeerId('a'));
    expect(link.isSecure, isTrue);
    expect(link.isPendingHandshake, isFalse);
    expect((identified, secured), (1, 1));
    expect(store.conversation('cB')!.peerAlias, 'scripted');
    expect(store.conversation('cB')!.secure, isTrue);
  });

  group('a forged or misdirected proof closes the link', () {
    test('a peerId that is not the hash of the claimed key', () async {
      await open();
      peer.sendDialerHello(
        peerId: testPeerId('a'),
        claimedKey: testIdentity('c').publicKey,
      );
      await expectRefused();
      expect(peer.frames, isEmpty, reason: 'no answer to a bad claim');
    });

    test(
      'an impostor with the victim peerId and key but its own key',
      () async {
        await open(dialer: testIdentity('c')); // 서명은 c의 키로
        await hello(
          peerId: testPeerId('a'),
          claimedKey: testIdentity('a').publicKey,
        );
        peer.sendAuth(
          await peer.proof(asDialer: true, ownKey: testIdentity('a').publicKey),
        );
        await expectRefused();
      },
    );

    test('a proof recorded from another session', () async {
      await open();
      await hello();
      final recorded = await peer.proof(asDialer: true);
      peer.sendAuth(recorded);
      await pumpEventQueue(times: 60);
      expect(
        link.remotePeerId,
        testPeerId('a'),
        reason: 'valid the first time',
      );

      await open(); // 새 세션(새 임시키): 같은 신원, 같은 서명
      await hello();
      peer.sendAuth(recorded);
      await expectRefused();
    });

    test('a proof that names another listener', () async {
      await open();
      await hello();
      peer.sendAuth(
        await peer.proof(asDialer: true, peerKey: testIdentity('c').publicKey),
      );
      await expectRefused();
    });

    test('a proof over other ephemeral keys', () async {
      await open();
      await hello();
      peer.sendAuth(
        await peer.proof(asDialer: true, ownEphemeral: List<int>.filled(32, 5)),
      );
      await expectRefused();
    });

    test('a listener-role signature offered as the dialer proof', () async {
      await open();
      await hello();
      peer.sendAuth(await peer.proof(asDialer: true, dialerRole: false));
      await expectRefused();
    });
  });
}
