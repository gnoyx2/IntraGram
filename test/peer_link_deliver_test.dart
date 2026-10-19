import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/test_identities.dart';

// 호스트가 파일 제어 프레임을 중계할 때 쓰는 전달 관찰: `deliverRawInner`는 절대 안 던지고 false와 (열린
// 링크의 봉인 오류 같은) 예외를 똑같이 "미전달"로 돌려줌. `sendRawInnerOrClose`는 미전달이면 링크를 닫아
// 상대가 프레임을 영영 못 받고 기다리지 않게 하고, 나갔으면 링크를 건드리지 않음
void main() {
  late PeerLink link;
  late CryptoSession session;
  final typing = <String, dynamic>{'k': 'typing', 'on': true};

  setUp(() async {
    final engine = CryptoEngine();
    session = await engine.createSession();
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
  });

  test(
    'a frame that goes out is delivered and leaves the link alone',
    () async {
      expect(await link.deliverRawInner(typing), isTrue);
      expect(await link.sendRawInnerOrClose(typing), isTrue);
      expect(link.isClosed, isFalse);
    },
  );

  test(
    'a seal error on an open link is undelivered, not a thrown error',
    () async {
      await session.seal(<String, dynamic>{'k': 'typing'}, seq: 1000);

      expect(await link.deliverRawInner(typing), isFalse);
      // 그 번호는 소모돼서 상대는 다음 프레임을 빠진 프레임으로 봄: 계속 쓰지 않고 닫음
      expect(link.isClosed, isTrue);
    },
  );

  test('sendRawInnerOrClose closes the link on that seal error', () async {
    await session.seal(<String, dynamic>{'k': 'typing'}, seq: 1000);
    var closedCallbacks = 0;
    link.onClosed = (_) => closedCallbacks++;

    expect(await link.sendRawInnerOrClose(typing), isFalse);

    expect(link.isClosed, isTrue);
    expect(closedCallbacks, 1, reason: 'the close cleanup ran exactly once');
  });

  test(
    'text seal failure marks the bubble failed and closes the link',
    () async {
      await session.seal(<String, dynamic>{'k': 'typing'}, seq: 1000);

      await link.sendText('cannot-send', ttlSeconds: 0);

      expect(link.isClosed, isTrue);
      expect(
        link.store
            .messages('cA')
            .singleWhere((m) => m.text == 'cannot-send')
            .delivery,
        DeliveryState.failed,
      );
    },
  );

  test('a queue over its cap is undelivered and the link is closed', () async {
    // 동기 구간에서 한도만큼 채움: 실제 전송은 직렬 큐에서 뒤따름
    final inFlight = [
      for (var i = 0; i < kMaxPendingOutboundFrames; i++)
        link.deliverRawInner(typing),
    ];

    expect(await link.sendRawInnerOrClose(typing), isFalse);

    expect(link.isClosed, isTrue);
    await Future.wait(inFlight); // 이미 큐에 든 프레임은 던지지 않고 끝남
  });

  test(
    'a link that is already closing reports undelivered and closes once',
    () async {
      var closedCallbacks = 0;
      link.onClosed = (_) => closedCallbacks++;
      final closing = link.close();

      expect(await link.sendRawInnerOrClose(typing), isFalse);
      await closing;

      expect(closedCallbacks, 1);
    },
  );
}
