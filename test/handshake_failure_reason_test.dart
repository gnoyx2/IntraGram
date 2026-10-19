import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/features/chat/widgets/chat_app_bar.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/link_registry_fixtures.dart' show identity;
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 내가 다이얼한 대화가 핸드셰이크에서 실패하면 '연결 끊김' 하나 대신 이유(다른 기기·증명 실패·
// 시간 초과)를 남기고, 재연결이 소켓에서 막히면 그 이유를 스낵바로 알림

List<SystemEventKind?> _lines(InMemoryStore store, String id) =>
    store.messages(id).map((m) => m.systemEvent?.kind).toList();

void main() {
  Future<(InMemoryStore, PeerLink, ScriptedPeer)> dial({
    String? expectedPeerId,
  }) async {
    final wire = StreamChannelController<dynamic>();
    final store = InMemoryStore()..upsertConversation(conv('cA', 'bob'));
    final link = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: store,
      identity: testIdentity('a', alias: 'alice', platform: 'test'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
      expectedPeerId: expectedPeerId,
    );
    final peer = await ScriptedPeer.create(
      testIdentity('b', alias: 'listener'),
      wire.foreign,
    );
    addTearDown(() async {
      await link.close();
      store.dispose();
    });
    await link.start();
    await pumpEventQueue(times: 30);
    return (store, link, peer);
  }

  test('another device at the dialled address leaves a warning line', () async {
    final (store, link, peer) = await dial(expectedPeerId: testPeerId('c'));
    peer.sendHello(signature: await peer.proof(asDialer: false));
    await pumpEventQueue(times: 60);

    expect(link.isClosed, isTrue);
    expect(_lines(store, 'cA'), [SystemEventKind.peerMismatch]);
  });

  test('a proof that does not verify says the device could not prove '
      'itself', () async {
    final (store, link, peer) = await dial();
    peer.sendHello(signature: List<int>.filled(64, 7));
    await pumpEventQueue(times: 60);

    expect(link.isClosed, isTrue);
    expect(_lines(store, 'cA'), [SystemEventKind.handshakeFailed]);
  });

  test('an unanswered dial says the handshake timed out', () async {
    final session = await CryptoEngine().createSession();
    final store = InMemoryStore()..upsertConversation(conv('cX', 'ghost'));
    addTearDown(store.dispose);
    final wire = StreamChannelController<dynamic>();
    wire.foreign.stream.listen((_) {});

    // 워치독만 가짜 시간으로 당김. 종료 정리는 실제 이벤트 큐와 가짜 타이머(소켓 닫기 2초 상한)를 오감
    final clock = FakeAsync();
    clock.run((_) {
      PeerLink(
        conversationId: 'cX',
        channel: wire.local,
        store: store,
        identity: testIdentity('e', alias: 'me', platform: 'Linux'),
        crypto: session,
        dialledByUs: true,
      ).start();
    });
    clock.elapse(kHandshakeTimeout + const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue();
      clock.elapse(const Duration(seconds: 1));
    }
    expect(_lines(store, 'cX'), [SystemEventKind.handshakeTimedOut]);
  });

  test('a reconnect the socket refuses reports why', () async {
    final store = InMemoryStore()
      ..upsertConversation(
        Conversation(
          id: 'c1',
          peerAlias: 'bob',
          peerPlatform: 'test',
          transport: PeerTransport.app,
          startedAt: DateTime(2026, 1, 1),
          peerHost: '192.168.1.20',
          peerPort: 7890,
        ),
      );
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
    });
    registry.debugDial = (_) async => throw const SocketException(
      'refused',
      osError: OSError('Connection refused', 61),
    );

    await expectLater(
      registry.reconnect('c1'),
      throwsA(
        isA<PeerUnreachableException>().having(
          (e) => e.reason,
          'reason',
          PeerUnreachableReason.refused,
        ),
      ),
    );
  });

  testWidgets('the offline banner explains a reconnect that failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineBanner(
            onReconnect: () async => throw PeerUnreachableException(
              'refused',
              reason: PeerUnreachableReason.refused,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reconnect'));
    await tester.pump();

    expect(find.textContaining('refused the connection'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget, reason: 'button is back');
  });
}
