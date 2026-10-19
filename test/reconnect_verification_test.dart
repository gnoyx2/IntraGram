import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/scripted_inbound.dart';
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

typedef _Pair = ({
  PeerLink linkA,
  PeerLink linkB,
  InMemoryStore storeA,
  InMemoryStore storeB,
});

// 같은 실행 안의 재연결(와이파이가 잠깐 끊김)은 같은 신원 키를 다시 증명함: 전에 맞춘 코드를 또 맞추지 않음
void main() {
  // 같은 대화(cA·cB)에 새 세션을 맺음. listenerTag를 바꾸면 B 자리에 다른 신원이 붙음
  Future<void> newSession(_Pair p, {String listenerTag = 'b'}) async {
    await p.linkA.close();
    await pumpEventQueue(times: 20);
    final wire = StreamChannelController<dynamic>();
    final dialer = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: p.storeA,
      identity: testIdentity('a', alias: 'alice-fox-11'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
    );
    final listener = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: p.storeB,
      identity: testIdentity(listenerTag, alias: 'bob-owl-22'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: false,
    );
    addTearDown(dialer.close);
    addTearDown(listener.close);
    await listener.start();
    await dialer.start();
    await pumpEventQueue(times: 80);
  }

  List<SystemEventKind> lines(InMemoryStore store, String id) =>
      store.messages(id).map((m) => m.systemEvent?.kind).nonNulls.toList();

  Future<_Pair> pair() async {
    final p = await connectedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);
    return p;
  }

  test('a chat both sides checked stays verified when the same devices '
      'reconnect', () async {
    final p = await pair();
    for (final (store, id) in [(p.storeA, 'cA'), (p.storeB, 'cB')]) {
      store
        ..setLocalVerified(id)
        ..setPeerVerified(id);
    }

    await newSession(p);

    for (final (store, id) in [(p.storeA, 'cA'), (p.storeB, 'cB')]) {
      expect(store.conversation(id)!.verified, isTrue, reason: id);
      expect(lines(store, id), contains(SystemEventKind.verifiedAgain));
      expect(lines(store, id), isNot(contains(SystemEventKind.encryptedAgain)));
      // 바뀐 숫자는 아무도 다시 안 맞춰서 '양쪽 다 확인' 줄은 없음
      expect(
        lines(store, id),
        isNot(contains(SystemEventKind.mutuallyVerified)),
      );
    }
    expect(p.storeA.conversation('cA')!.sas, p.storeB.conversation('cB')!.sas);
  });

  test('only my own earlier check carries over: the peer confirms again '
      'on its own', () async {
    final p = await pair();
    p.storeA.setLocalVerified('cA');
    p.storeB.setPeerVerified('cB');

    await newSession(p);

    final a = p.storeA.conversation('cA')!;
    final b = p.storeB.conversation('cB')!;
    expect((a.localVerified, a.peerVerified), (true, false));
    expect((b.localVerified, b.peerVerified), (false, true));
    expect(lines(p.storeA, 'cA').last, SystemEventKind.verifiedAgain);
    expect(lines(p.storeB, 'cB').last, SystemEventKind.encryptedAgain);
  });

  test('another identity on the other end clears my check', () async {
    final p = await pair();
    p.storeA
      ..setLocalVerified('cA')
      ..setPeerVerified('cA');

    await newSession(p, listenerTag: 'c');

    final a = p.storeA.conversation('cA')!;
    expect(a.localVerified, isFalse);
    expect(a.peerId, testPeerId('c'));
    expect(
      lines(p.storeA, 'cA'),
      isNot(contains(SystemEventKind.verifiedAgain)),
    );
  });

  test(
    'an inbound reconnect merged into the old chat keeps my check',
    () async {
      final store = InMemoryStore();
      final registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: testIdentity('a', alias: 'me', platform: 'test'),
      );
      addTearDown(() async {
        await registry.disposeAll();
        store.dispose();
      });
      final first = await connectScriptedInbound(
        registry,
        host: '192.168.1.20',
        identity: testIdentity('b'),
      );
      final id = store.conversations.single.id;
      store
        ..setLocalVerified(id)
        ..setPeerVerified(id);
      await first.channel.sink.close();
      await pumpEventQueue(times: 30);
      expect(store.conversation(id)!.online, isFalse);

      await connectScriptedInbound(
        registry,
        host: '192.168.1.20',
        identity: testIdentity('b'),
      );

      expect(store.conversations, hasLength(1));
      final c = store.conversation(id)!;
      expect((c.localVerified, c.peerVerified), (true, false));
      expect(lines(store, id).last, SystemEventKind.verifiedAgain);
    },
  );
  test(
    'dialling an old chat again keeps my check for the same device',
    () async {
      final store = InMemoryStore();
      final registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: testIdentity('a', alias: 'me', platform: 'test'),
      );
      addTearDown(() async {
        await registry.disposeAll();
        store.dispose();
      });
      // 다음 다이얼에 정직하게 답하는 리스너(b)
      Future<ScriptedPeer> listenAs(String tag) async {
        final wire = StreamChannelController<dynamic>();
        registry.debugDial = (_) async => wire.local;
        return ScriptedPeer.create(testIdentity(tag), wire.foreign);
      }

      Future<void> answer(ScriptedPeer listener) async {
        await pumpEventQueue(times: 30);
        listener.sendHello(signature: await listener.proof(asDialer: false));
        await pumpEventQueue(times: 80);
      }

      var listener = await listenAs('b');
      final id = await registry.connectManual(host: '192.168.1.20', port: 7890);
      await answer(listener);
      store
        ..setLocalVerified(id)
        ..setPeerVerified(id);
      await listener.channel.sink.close();
      await pumpEventQueue(times: 30);

      listener = await listenAs('b');
      final reconnecting = registry.reconnect(id);
      await answer(listener);
      await reconnecting;

      final c = store.conversation(id)!;
      expect(c.secure, isTrue);
      expect((c.localVerified, c.peerVerified), (true, false));
      expect(lines(store, id).last, SystemEventKind.verifiedAgain);
    },
  );
}
