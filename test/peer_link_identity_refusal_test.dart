import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 앱 피어 링크의 신원 증명 거절·타임아웃(리스너 쪽): 요청 전이거나 중복된 auth 프레임,
// 서명 키가 없는 리스너 신원, 핸드셰이크 시한까지 도착하지 않는 auth 증명은 모두 링크를 닫음

void main() {
  late InMemoryStore store;
  late PeerLink link;
  late ScriptedPeer peer;
  var identified = 0;
  var secured = 0;

  // 진짜 리스너 링크(B) 하나와 그 반대편 스크립트 다이얼러를 엶
  Future<void> open({AppIdentity? listener, AppIdentity? dialer}) async {
    final wire = StreamChannelController<dynamic>();
    final openStore = store = InMemoryStore()
      ..upsertConversation(conv('cB', 'peer'));
    identified = 0;
    secured = 0;
    final openLink = link = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: openStore,
      identity: listener ?? testIdentity('b', alias: 'host', platform: 'test'),
      crypto: await CryptoEngine().createSession(),
    );
    openLink
      ..onAppPeerIdentified = (() => identified++)
      ..onSecure = (() => secured++);
    peer = await ScriptedPeer.create(
      dialer ?? testIdentity('a', alias: 'dialer'),
      wire.local,
    );
    addTearDown(() async {
      await openLink.close();
      openStore.dispose();
    });
    await openLink.start();
  }

  // 다이얼러가 hello를 보내고 리스너의 답을 받은 뒤 키 합의까지 끝냄
  Future<void> hello({String? peerId, List<int>? claimedKey}) async {
    peer.sendDialerHello(peerId: peerId, claimedKey: claimedKey);
    await pumpEventQueue(times: 60);
    await peer.completeHandshake();
  }

  Future<void> expectRefused({bool placeholderWiped = true}) async {
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);
    expect(link.isSecure, isFalse);
    expect(identified + secured, 0, reason: 'nothing was reported upward');
    if (placeholderWiped) expect(store.conversation('cB'), isNull);
  }

  test('an auth nobody asked for closes the link', () async {
    await open();
    peer.sendAuth(List<int>.filled(64, 1)); // hello 전
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue);
    expect(link.remotePeerId, isNull);

    await open();
    await hello();
    peer.sendAuth(await peer.proof(asDialer: true));
    await pumpEventQueue(times: 60);
    expect(link.isSecure, isTrue);
    peer.sendAuth(await peer.proof(asDialer: true)); // 이미 증명된 뒤 또
    await pumpEventQueue(times: 60);
    expect(link.isClosed, isTrue, reason: 'a second proof is a replay');
  });

  test('an identity without a signing key never links', () async {
    await open(
      listener: AppIdentity(peerId: 'b' * 32, alias: 'host', platform: 'test'),
    );
    peer.sendDialerHello();
    await expectRefused();
    expect(peer.frames, isEmpty);
  });

  test('a proof that never comes closes the link at the timeout', () async {
    final wire = StreamChannelController<dynamic>();
    final timeoutStore = InMemoryStore()
      ..upsertConversation(conv('cB', 'peer'));
    addTearDown(timeoutStore.dispose);
    final session = await CryptoEngine().createSession();
    final scripted = await ScriptedPeer.create(
      testIdentity('a', alias: 'dialer'),
      wire.local,
    );
    fakeAsync((async) {
      final timeoutLink = PeerLink(
        conversationId: 'cB',
        channel: wire.foreign,
        store: timeoutStore,
        identity: testIdentity('b', alias: 'host', platform: 'test'),
        crypto: session,
      );
      timeoutLink.start();
      scripted.sendDialerHello();
      async.flushMicrotasks();
      expect(scripted.frames, isNotEmpty, reason: 'the listener answered');
      expect(timeoutLink.isClosed, isFalse);
      expect(timeoutLink.isSecure, isFalse, reason: 'not proven yet');

      async.elapse(kHandshakeTimeout + const Duration(seconds: 1));
      expect(timeoutLink.isClosed, isTrue, reason: 'watchdog fired');
    });
  });
}
