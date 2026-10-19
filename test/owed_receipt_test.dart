import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/link_registry_fixtures.dart' show identity;
import 'support/test_identities.dart';

// 링크가 없어 못 간 읽음·소각 신호는 store에 남았다가 다음 링크가 열리면 나감
// 그래서 상대가 오프라인에서 읽거나 소각해도 보낸 쪽 사본이 24시간 상한까지 남지 않음

EphemeralMessage _timed(String id, String room, MessageDirection direction) =>
    EphemeralMessage(
      id: id,
      conversationId: room,
      direction: direction,
      kind: MessageKind.text,
      senderAlias: direction == MessageDirection.outgoing ? 'alice' : 'bob',
      createdAt: DateTime(2026, 1, 1),
      text: 'hi',
      ttlSeconds: 30,
      delivery: direction == MessageDirection.outgoing
          ? DeliveryState.delivered
          : DeliveryState.read,
    );

void main() {
  test('owed receipts are kept per chat, taken once and dropped with the '
      'chat', () {
    final store = InMemoryStore()
      ..upsertConversation(conv('c1', 'bob'))
      ..upsertConversation(conv('c2', 'eve'));
    addTearDown(store.dispose);

    store
      ..oweReads('c1', ['r1', 'r2'])
      ..oweBurn('c1', 'r2')
      ..oweReads('c2', ['x'])
      ..oweReads('gone', ['y']);

    final owed = store.takeOwed('c1');
    expect(owed.reads, ['r1'], reason: 'a burn supersedes its read');
    expect(owed.burns, ['r2']);
    expect(store.takeOwed('c1').reads, isEmpty);
    expect(store.takeOwed('gone').reads, isEmpty);

    store.wipeConversation('c2');
    expect(store.takeOwed('c2').reads, isEmpty);
  });

  test('the next secure link sends the owed read and burn', () async {
    final engine = CryptoEngine();
    final wire = StreamChannelController<dynamic>();
    final storeA = InMemoryStore()..upsertConversation(conv('cA', 'bob'));
    final storeB = InMemoryStore()..upsertConversation(conv('cB', 'alice'));
    storeA
      ..addMessage(_timed('m1', 'cA', MessageDirection.outgoing))
      ..addMessage(_timed('m2', 'cA', MessageDirection.outgoing));
    // B는 오프라인일 때 m1을 읽고 m2는 이미 소각함
    storeB
      ..addMessage(_timed('m1', 'cB', MessageDirection.incoming))
      ..oweReads('cB', ['m1'])
      ..oweBurn('cB', 'm2');
    final linkA = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: storeA,
      identity: testIdentity('a', alias: 'alice', platform: 'x'),
      crypto: await engine.createSession(),
      dialledByUs: true,
    );
    final linkB = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: storeB,
      identity: testIdentity('b', alias: 'bob', platform: 'x'),
      crypto: await engine.createSession(),
    );
    addTearDown(() async {
      await linkA.close();
      await linkB.close();
      storeA.dispose();
      storeB.dispose();
    });

    await linkB.start();
    await linkA.start();
    await pumpEventQueue(times: 80);

    expect(storeA.messageById('m1')?.burnAt, isNotNull);
    expect(storeA.messageById('m2'), isNull);
    final left = storeB.takeOwed('cB');
    expect([...left.reads, ...left.burns], isEmpty);
  });

  test('reads and burns with no live link are owed to the chat', () async {
    final tmp = Directory.systemTemp.createTempSync('intragram_owed');
    final store = InMemoryStore()..upsertConversation(conv('c1', 'peer'));
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => tmp.path,
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
      tmp.deleteSync(recursive: true);
    });
    store
      ..addMessage(
        _timed(
          'in1',
          'c1',
          MessageDirection.incoming,
        ).copyWith(delivery: DeliveryState.sent),
      )
      ..addMessage(_timed('out1', 'c1', MessageDirection.outgoing));

    await registry.markRoomRead('c1');
    registry.deleteMessageForEveryone('out1');
    await pumpEventQueue();

    final owed = store.takeOwed('c1');
    expect(owed.reads, ['in1']);
    expect(owed.burns, ['out1']);
  });

  test('a read still queued for the handshake is owed again when the link '
      'closes', () async {
    final wire = StreamChannelController<dynamic>();
    wire.foreign.stream.listen((_) {});
    final store = InMemoryStore()..upsertConversation(conv('cA', 'bob'));
    addTearDown(store.dispose);
    final link = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: store,
      identity: testIdentity('a', alias: 'alice', platform: 'x'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
    );

    await link.sendReadReceipts(['r1']);
    await link.sendBurn('b1');
    await link.close();

    final owed = store.takeOwed('cA');
    expect(owed.reads, ['r1']);
    expect(owed.burns, ['b1']);
  });
}
