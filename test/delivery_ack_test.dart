import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/peer_auth_rig.dart';
import 'support/test_identities.dart';

// 전송 단계: 핸드셰이크 대기 큐에선 sending, 소켓에 쓰면 sent, 상대 ack로 delivered
// ack는 바로 앞 홉의 수신 확인이라 방 멤버에게 중계하지 않음

EphemeralMessage _msg(
  String id,
  String room,
  DeliveryState delivery, {
  MessageDirection direction = MessageDirection.outgoing,
}) => EphemeralMessage(
  id: id,
  conversationId: room,
  direction: direction,
  kind: MessageKind.text,
  senderAlias: 'me',
  createdAt: DateTime(2026, 1, 1),
  text: 'hi',
  delivery: delivery,
);

void main() {
  test('a message queued before the handshake is sent only when written, '
      'then delivered by the peer ack', () async {
    final engine = CryptoEngine();
    final wire = StreamChannelController<dynamic>();
    final storeA = InMemoryStore()..upsertConversation(conv('cA', 'bob'));
    final storeB = InMemoryStore()..upsertConversation(conv('cB', 'alice'));
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

    await linkA.sendText('early', ttlSeconds: 0);
    expect(
      chat(storeA, 'cA').single.delivery,
      DeliveryState.sending,
      reason: 'queued for the handshake is not on the socket yet',
    );

    await linkB.start();
    await linkA.start();
    await pumpEventQueue(times: 80);

    expect(chat(storeB, 'cB').single.text, 'early');
    expect(chat(storeA, 'cA').single.delivery, DeliveryState.delivered);
  });

  test('an ack only moves our own message and is never relayed', () async {
    final rig = await AuthRig.create();
    rig.storeB
      ..upsertConversation(conv('other', 'someone'))
      ..addMessage(_msg('mine', 'cB', DeliveryState.sent))
      ..addMessage(_msg('elsewhere', 'other', DeliveryState.sent));

    await rig.sendFromA(<String, dynamic>{'k': 'ack', 'id': 'mine'});
    await rig.sendFromA(<String, dynamic>{'k': 'ack', 'id': 'elsewhere'});

    expect(rig.storeB.messageById('mine')!.delivery, DeliveryState.delivered);
    expect(rig.storeB.messageById('elsewhere')!.delivery, DeliveryState.sent);
    expect(rig.relayed, isEmpty);
  });

  test('delivery moves forward only and keeps failed and read', () {
    final store = InMemoryStore()..upsertConversation(conv('c1', 'peer'));
    addTearDown(store.dispose);
    DeliveryState state(String id) => store.messageById(id)!.delivery;

    store.addMessage(_msg('late', 'c1', DeliveryState.sending));
    store.advanceDelivery('late', DeliveryState.delivered);
    store.advanceDelivery('late', DeliveryState.sent); // 늦게 온 소켓 기록
    expect(state('late'), DeliveryState.delivered);

    store.addMessage(_msg('failed', 'c1', DeliveryState.failed));
    store.advanceDelivery('failed', DeliveryState.delivered);
    expect(state('failed'), DeliveryState.failed, reason: 'retry stays shown');

    // 일부가 이미 읽은 방 메시지를 다시 보내도 ack가 read를 내리지 않음
    store.addMessage(_msg('read', 'c1', DeliveryState.failed));
    store.applyReadReceipt('read', 'peer0');
    store.setDelivery('read', DeliveryState.sending);
    store.advanceDelivery('read', DeliveryState.delivered);
    expect(state('read'), DeliveryState.read);

    store.addMessage(
      _msg(
        'theirs',
        'c1',
        DeliveryState.sent,
        direction: MessageDirection.incoming,
      ),
    );
    store.advanceDelivery('theirs', DeliveryState.delivered);
    expect(state('theirs'), DeliveryState.sent);
  });
}
