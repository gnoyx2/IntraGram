import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 자기 자신의 신원을 밝히는 hello: 정상 기기는 자기한테 다이얼하지 않음(탐지도 자기 광고를 거름). 중간자가
// 내 hello를 내 서버로 되돌려(반사) 서명까지 받아 내면 나와 나 사이의 링크가 서 버리므로, 서명을 만들거나
// 검증하기 전에 거절함
void main() {
  test('a listener refuses a dialer that claims its own identity', () async {
    final wire = StreamChannelController<dynamic>();
    final store = InMemoryStore()..upsertConversation(conv('cB', 'peer'));
    addTearDown(store.dispose);
    final link = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: store,
      identity: testIdentity('b', alias: 'host'),
      crypto: await CryptoEngine().createSession(),
    );
    addTearDown(link.close);
    final reflected = await ScriptedPeer.create(testIdentity('b'), wire.local);
    await link.start();

    reflected.sendDialerHello();
    await pumpEventQueue(times: 60);

    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);
    expect(reflected.frames, isEmpty, reason: 'no signature for our own key');
    expect(store.conversation('cB'), isNull, reason: 'placeholder wiped');
  });

  test('a dialer refuses a listener that claims its own identity', () async {
    final wire = StreamChannelController<dynamic>();
    final store = InMemoryStore()..upsertConversation(conv('cA', 'bob'));
    addTearDown(store.dispose);
    final link = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: store,
      identity: testIdentity('a', alias: 'alice'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
    );
    addTearDown(link.close);
    final reflected = await ScriptedPeer.create(
      testIdentity('a'),
      wire.foreign,
    );
    await link.start();
    await pumpEventQueue(times: 30);

    // 서명까지 맞는 반사 hello: 자기 검사만 이걸 막음
    reflected.sendHello(signature: await reflected.proof(asDialer: false));
    await pumpEventQueue(times: 60);

    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);
    expect(link.isSecure, isFalse);
    expect(reflected.frames.where((f) => f['t'] == 'auth'), isEmpty);
    expect(store.conversation('cA'), isNotNull, reason: 'the dial is ours');
  });
}
