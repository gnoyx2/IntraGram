import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/test_identities.dart';

// 링크가 닫힐 때 상대 확인을 못 받은 내 메시지는 재시도할 수 있게 failed로 내려감
// 재시도는 같은 id로 다시 보내서 원본을 이미 받은 상대에게 사본이 안 생김

EphemeralMessage _text(
  String id,
  String room,
  MessageDirection direction,
  DeliveryState delivery,
) => EphemeralMessage(
  id: id,
  conversationId: room,
  direction: direction,
  kind: MessageKind.text,
  senderAlias: direction == MessageDirection.outgoing ? 'alice' : 'bob',
  createdAt: DateTime(2026, 1, 1),
  text: 'hi',
  delivery: delivery,
);

void main() {
  test('a message still waiting for the handshake fails when the link '
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

    await link.sendText('early', ttlSeconds: 0);
    expect(chat(store, 'cA').single.delivery, DeliveryState.sending);

    await link.close();
    expect(chat(store, 'cA').single.delivery, DeliveryState.failed);
  });

  test('a written message with no ack fails when the link closes, an acked '
      'one stays delivered', () async {
    final p = await connectedPair();
    addTearDown(() async {
      await p.linkA.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });

    await p.linkA.sendText('seen', ttlSeconds: 0);
    await pumpEventQueue(times: 40);
    final seen = chat(p.storeA, 'cA').single.id;
    expect(p.storeA.messageById(seen)!.delivery, DeliveryState.delivered);

    // 상대가 이 대화를 잊으면 받아도 ack가 안 돌아옴 (전선에서 사라진 것과 같음)
    p.storeB.wipeConversation('cB');
    await p.linkA.sendText('lost', ttlSeconds: 0);
    await pumpEventQueue(times: 40);
    final lost = chat(p.storeA, 'cA').firstWhere((m) => m.text == 'lost').id;
    expect(p.storeA.messageById(lost)!.delivery, DeliveryState.sent);

    await p.linkB.close();
    await pumpEventQueue(times: 40);
    expect(p.storeA.messageById(lost)!.delivery, DeliveryState.failed);
    expect(p.storeA.messageById(seen)!.delivery, DeliveryState.delivered);
  });

  test('a repeated message id is acked again without a second copy or '
      'unread bump', () async {
    final p = await connectedPair();
    addTearDown(() async {
      await p.linkA.close();
      await p.linkB.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });

    await p.linkA.sendText('once', ttlSeconds: 0);
    await pumpEventQueue(times: 40);
    final sent = chat(p.storeA, 'cA').single;
    expect(p.storeB.conversation('cB')!.unread, 1);

    p.storeA.setDelivery(sent.id, DeliveryState.sending);
    await p.linkA.resendText(p.storeA.messageById(sent.id)!);
    await pumpEventQueue(times: 40);

    expect(chat(p.storeB, 'cB'), hasLength(1));
    expect(p.storeB.conversation('cB')!.unread, 1);
    expect(p.storeA.messageById(sent.id)!.delivery, DeliveryState.delivered);
  });

  test('retrying a failed message on a live link keeps its id', () async {
    final tmp = Directory.systemTemp.createTempSync('intragram_unacked');
    final store = InMemoryStore();
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: testIdentity('a', alias: 'alice', platform: 'x'),
      chooseDirectory: (_) async => tmp.path,
    );
    final peerStore = InMemoryStore()..upsertConversation(conv('cB', 'alice'));
    final wire = StreamChannelController<dynamic>();
    final peer = PeerLink(
      conversationId: 'cB',
      channel: wire.local,
      store: peerStore,
      identity: testIdentity('b', alias: 'bob', platform: 'x'),
      crypto: await CryptoEngine().createSession(),
    );
    addTearDown(() async {
      await peer.close();
      await registry.disposeAll();
      store.dispose();
      peerStore.dispose();
      tmp.deleteSync(recursive: true);
    });
    await peer.start();
    final id = await registry.debugAdoptDialledChannel(
      wire.foreign,
      remoteHost: '192.168.1.99',
      remotePort: 12345,
    );
    await pumpEventQueue(times: 80);
    expect(registry.linkFor(id)?.isSecure, isTrue);

    // 상대는 원본을 받았는데 확인이 오기 전에 옛 링크가 끊겼던 메시지
    peerStore.addMessage(
      _text('m1', 'cB', MessageDirection.incoming, DeliveryState.sent),
    );
    store.addMessage(
      _text('m1', id, MessageDirection.outgoing, DeliveryState.failed),
    );

    registry.resendFailed('m1');
    await pumpEventQueue(times: 40);

    expect(chat(store, id).single.id, 'm1');
    expect(store.messageById('m1')!.delivery, DeliveryState.delivered);
    expect(chat(peerStore, 'cB'), hasLength(1));
  });
}
