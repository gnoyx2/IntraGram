import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_auth.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 커밋-후-공개 순서: 리스너는 다이얼러 임시키를 모른 채 자기 키를 정하고, 다이얼러는 리스너가 서명한
// hello를 받기 전엔 키를 공개하지 않음. 어느 자리의 중간자도 상대 키를 본 뒤 SAS를 맞출 키를 고르지 못함
void main() {
  late InMemoryStore store;
  late PeerLink link;
  late ScriptedPeer peer;

  Future<void> open({required bool linkDials}) async {
    final wire = StreamChannelController<dynamic>();
    final openStore = store = InMemoryStore()
      ..upsertConversation(conv('c', 'peer'));
    final openLink = link = PeerLink(
      conversationId: 'c',
      channel: wire.local,
      store: openStore,
      identity: testIdentity('a', alias: 'link', platform: 'test'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: linkDials,
    );
    peer = await ScriptedPeer.create(testIdentity('b'), wire.foreign);
    addTearDown(() async {
      await openLink.close();
      openStore.dispose();
    });
    await openLink.start();
    await pumpEventQueue(times: 30);
  }

  Future<void> expectClosed() async {
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue);
    expect(link.isSecure, isFalse);
    expect(link.remotePeerId, isNull);
  }

  group('as listener', () {
    test('agrees on keys only after the committed key is revealed', () async {
      await open(linkDials: false);
      peer.sendDialerHello();
      await pumpEventQueue(times: 60);
      expect(peer.linkHello['pub'], isNotNull, reason: 'listener answered');
      expect(link.sasDigits, isNull, reason: 'dialer key still unknown');

      peer.sendAuth(await peer.proof(asDialer: true));
      await pumpEventQueue(times: 60);
      await peer.completeHandshake();
      expect(link.isSecure, isTrue);
      expect(link.sasDigits, peer.session.sasDigits);
    });

    test('refuses a reveal that does not open the commitment', () async {
      await open(linkDials: false);
      peer.sendDialerHello();
      await pumpEventQueue(times: 60);
      // 커밋한 키 대신 리스너 키를 본 뒤 고른 다른 키를 공개하고, 그 키로 정직하게 서명함
      final swapped = await CryptoEngine().createSession();
      peer.sendAuth(
        await peer.proof(asDialer: true, ownEphemeral: swapped.publicKey),
        reveal: swapped.publicKey,
      );
      await expectClosed();
      expect(store.conversation('c'), isNull, reason: 'placeholder wiped');
    });

    test('refuses a dialer hello that shows its key up front', () async {
      await open(linkDials: false);
      peer.sendDialerHello(withEphemeral: true);
      await expectClosed();
      expect(peer.frames, isEmpty, reason: 'no answer to an old-style hello');
    });

    test('refuses a dialer hello without a commitment', () async {
      await open(linkDials: false);
      peer.sendDialerHello(withCommitment: false);
      await expectClosed();
      expect(peer.frames, isEmpty);
    });
  });

  group('as dialer', () {
    test('reveals its key only after a signed listener hello', () async {
      await open(linkDials: true);
      expect(peer.frames.single['t'], 'hello');
      expect(peer.frames.single.containsKey('pub'), isFalse);

      peer.sendHello(signature: await peer.proof(asDialer: false));
      await pumpEventQueue(times: 60);
      expect(
        ephemeralCommitment(
          ephemeral: peer.linkRevealed,
          identityKey: peer.linkKey,
        ),
        peer.linkCommitment,
        reason: 'the revealed key is the committed one',
      );
      await peer.completeHandshake(asDialer: false);
      expect(link.sasDigits, peer.session.sasDigits);
    });

    test('refuses a listener hello that carries a commitment', () async {
      await open(linkDials: true);
      peer.sendHello(
        signature: await peer.proof(asDialer: false),
        commitment: List<int>.filled(32, 1),
      );
      await expectClosed();
      expect(peer.frames.where((f) => f['t'] == 'auth'), isEmpty);
    });

    test('refuses a listener hello without a key', () async {
      await open(linkDials: true);
      peer.sendHello(
        signature: await peer.proof(asDialer: false),
        withEphemeral: false,
      );
      await expectClosed();
      expect(peer.frames.where((f) => f['t'] == 'auth'), isEmpty);
    });
  });
}
