import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/network_guard.dart' show SecurityException;
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/test_identities.dart';

// 보내던 중 링크가 닫히면 못 보낸 것(false)일 뿐이지 던질 일이 아님: 호스트 중계처럼 결과를
// 기다리지 않고 흘려보내는 호출부에서 처리 안 된 비동기 오류가 되면 안 됨. 링크가 열려 있는데
// 봉인이 던지면 진짜 오류라 그대로 올라와야 함
void main() {
  late PeerLink link;

  setUp(() async {
    final engine = CryptoEngine();
    final session = await engine.createSession();
    final wire = StreamChannelController<dynamic>();
    final storeA = InMemoryStore()..upsertConversation(conv('cA', 'bob'));
    final storeB = InMemoryStore()..upsertConversation(conv('cB', 'alice'));
    link = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: storeA,
      identity: testIdentity('a', alias: 'alice', platform: 'x'),
      crypto: session,
      dialledByUs: true,
    );
    final peer = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: storeB,
      identity: testIdentity('b', alias: 'bob', platform: 'x'),
      crypto: await engine.createSession(),
    );
    addTearDown(() async {
      await link.close();
      await peer.close();
      storeA.dispose();
      storeB.dispose();
    });
    await peer.start();
    await link.start();
    await pumpEventQueue(times: 60);
    expect(link.isSecure, isTrue);
    // 이 세션의 seal 워터마크를 미리 올려 둠: 링크의 다음 프레임 seq가 "이미 씀"으로 거부되게
    // 해서, 봉인이 던지는 상황을 결정적으로 만듦
    await session.seal(<String, dynamic>{'k': 'typing'}, seq: 1000);
  });

  test(
    'a seal failure on a link that is closing is an undelivered frame',
    () async {
      final sent = link.sendRawInner(<String, dynamic>{
        'k': 'typing',
        'on': true,
      });
      scheduleMicrotask(() => unawaited(link.close()));
      expect(await sent, isFalse);
    },
  );

  test('a seal failure on an open link is still an error', () async {
    await expectLater(
      link.sendRawInner(<String, dynamic>{'k': 'typing', 'on': true}),
      throwsA(isA<SecurityException>()),
    );
  });
}
