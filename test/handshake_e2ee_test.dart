import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/test_identities.dart';

void main() {
  test(
    'handshake derives a matching SAS and marks both sides secure',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      final cA = p.storeA.conversation('cA')!;
      final cB = p.storeB.conversation('cB')!;

      expect(cA.secure, isTrue);
      expect(cB.secure, isTrue);
      expect(p.linkA.isSecure, isTrue);
      expect(cA.sas, isNotNull);
      expect(cA.sas!.length, 6);
      expect(
        cA.sas,
        cB.sas,
        reason: 'both peers must show the same fingerprint',
      );
      expect(
        cA.verified,
        isFalse,
        reason: 'not verified until the user confirms',
      );
    },
  );

  test(
    'hello carries each side\'s stable peerId, exposed as remotePeerId',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      expect(
        p.linkA.remotePeerId,
        testPeerId('b'),
        reason: 'A learns B\'s peerId',
      );
      expect(
        p.linkB.remotePeerId,
        testPeerId('a'),
        reason: 'B learns A\'s peerId',
      );
      expect(p.linkA.sasDigits, isNotNull);
      expect(p.linkA.sasDigits, p.linkB.sasDigits);
    },
  );

  test('hello carries the dialling peer\'s real listening port, overwriting '
      'the TCP-accept ephemeral port acceptInbound staged it with', () async {
    // B는 인바운드 소켓을 accept해서 그 대화가 A의 진짜 서버 포트가 아니라 TCP 원격(클라이언트 쪽 ephemeral) 포트로 만들어짐:
    // hello가 A의 진짜 리스닝 포트로 고쳐야 함
    final p = await connectedPair(localPortA: 51820, remotePortB: 54321);
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    expect(p.storeB.conversation('cB')!.peerPort, 51820);
  });

  test(
    'an encrypted message crosses the link and decrypts on the peer',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      await p.linkA.sendText('meet at six', ttlSeconds: 0);
      await pumpEventQueue(times: 60);

      final received = chat(p.storeB, 'cB');
      expect(received, hasLength(1));
      expect(received.single.text, 'meet at six');
      expect(received.single.direction, MessageDirection.incoming);
      expect(
        chat(p.storeA, 'cA').single.delivery,
        DeliveryState.delivered,
        reason: 'the peer acks what it received',
      );
    },
  );

  test('read receipt arms the burn timer on both sides and it fires', () async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    await p.linkA.sendText('self destruct', ttlSeconds: 1);
    await pumpEventQueue(times: 60);

    final readIds = p.storeB.markIncomingRead('cB');
    await p.linkB.sendReadReceipts(readIds);
    await pumpEventQueue(times: 60);

    expect(chat(p.storeA, 'cA').single.delivery, DeliveryState.read);
    expect(chat(p.storeA, 'cA').single.burnAt, isNotNull);
    expect(chat(p.storeB, 'cB').single.burnAt, isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 1300));
    await pumpEventQueue(times: 20);

    expect(chat(p.storeA, 'cA'), isEmpty, reason: 'A burned its copy');
    expect(chat(p.storeB, 'cB'), isEmpty, reason: 'B burned its copy');
  });

  test('an oversized raw frame is dropped and the link is torn down', () async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    p.linkA.channel.sink.add('x' * (kMaxFrameBytes + 1));
    await pumpEventQueue(times: 40);

    expect(p.linkB.isClosed, isTrue);
  });

  test(
    'the handshake drops an "Encrypted" system line into both stores',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      for (final (store, id) in [(p.storeA, 'cA'), (p.storeB, 'cB')]) {
        final sys = store
            .messages(id)
            .where((m) => m.kind == MessageKind.system)
            .toList();
        expect(sys, hasLength(1));
        expect(sys.single.systemEvent?.kind, SystemEventKind.encrypted);
      }
    },
  );

  test(
    'a new session in a chat that had a code says the code changed',
    () async {
      final p = await connectedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);
      await p.linkA.close();
      await pumpEventQueue(times: 20);

      // 같은 대화로 새 세션을 맺음 (재연결과 같음): 검증은 새로 해야 해서 이유를 알림
      final wire = StreamChannelController<dynamic>();
      final dialer = PeerLink(
        conversationId: 'cA',
        channel: wire.local,
        store: p.storeA,
        identity: testIdentity('a', alias: 'alice-fox-11', platform: 'Linux'),
        crypto: await CryptoEngine().createSession(),
        dialledByUs: true,
      );
      final listener = PeerLink(
        conversationId: 'cB',
        channel: wire.foreign,
        store: p.storeB,
        identity: testIdentity('b', alias: 'bob-owl-22', platform: 'macOS'),
        crypto: await CryptoEngine().createSession(),
        dialledByUs: false,
      );
      addTearDown(dialer.close);
      addTearDown(listener.close);
      await listener.start();
      await dialer.start();
      await pumpEventQueue(times: 60);

      for (final (store, id) in [(p.storeA, 'cA'), (p.storeB, 'cB')]) {
        final lines = store
            .messages(id)
            .map((m) => m.systemEvent?.kind)
            .nonNulls
            .toList();
        expect(lines.first, SystemEventKind.encrypted);
        expect(lines.last, SystemEventKind.encryptedAgain);
      }
    },
  );

  test(
    'an unanswered handshake tears the link down after the timeout',
    () async {
      final session = await CryptoEngine().createSession();
      final store = InMemoryStore()..upsertConversation(conv('cX', 'ghost'));
      addTearDown(store.dispose);

      final wire = StreamChannelController<dynamic>();
      wire.foreign.stream.listen((_) {}); // hello를 절대 안 보내는 조용한 피어

      fakeAsync((async) {
        final link = PeerLink(
          conversationId: 'cX',
          channel: wire.local,
          store: store,
          identity: testIdentity('e', alias: 'me', platform: 'Linux'),
          crypto: session,
          dialledByUs: true,
        );
        link.start();
        async.flushMicrotasks();
        expect(link.isClosed, isFalse);

        async.elapse(kHandshakeTimeout + const Duration(seconds: 1));
        expect(link.isClosed, isTrue, reason: 'watchdog fired');
      });
    },
  );
}
