import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/test_identities.dart';

Conversation _conv(String id, String peerAlias) => Conversation(
  id: id,
  peerAlias: peerAlias,
  peerPlatform: 'test',
  transport: PeerTransport.app,
  startedAt: DateTime(2026, 1, 1),
  online: true,
);

List<EphemeralMessage> _chat(InMemoryStore store, String id) =>
    store.messages(id).where((m) => m.kind != MessageKind.system).toList();

// `test/support/handshake_pair.dart`의 `connectedPair`와 같은 와이어링이지만,
// A→B 방향으로 실제 전선에 나간 raw 프레임을 [captured]에 남기는 탭을 끼워
// 넣음: 리플레이 테스트 전용이라 공용 fixture는 안 건드리고 여기서만 씀
Future<
  ({
    PeerLink linkA,
    PeerLink linkB,
    InMemoryStore storeA,
    InMemoryStore storeB,
    List<String> captured,
  })
>
_connectTappedPair({bool Function(String raw)? drop}) async {
  final engine = CryptoEngine();
  final wire = StreamChannelController<dynamic>();
  final storeA = InMemoryStore()..upsertConversation(_conv('cA', 'bob-owl-22'));
  final storeB = InMemoryStore()
    ..upsertConversation(_conv('cB', 'alice-fox-11'));

  final captured = <String>[];
  // 단일 구독 스트림이라 linkB가 구독하기 전에 .map()으로 감싸야 함: 그래야
  // linkB의 정상 수신을 방해하지 않으면서 지나가는 프레임을 옆에서 기록함
  final channelB = StreamChannel<dynamic>(
    wire.foreign.stream
        .map((raw) {
          if (raw is String) captured.add(raw);
          return raw;
        })
        // 능동 중간자가 프레임을 골라 버리는 상황 (키는 없어서 내용은 못 바꿈)
        .where((raw) => !(raw is String && (drop?.call(raw) ?? false))),
    wire.foreign.sink,
  );

  final linkA = PeerLink(
    conversationId: 'cA',
    channel: wire.local,
    store: storeA,
    identity: testIdentity('a', alias: 'alice-fox-11', platform: 'Linux'),
    crypto: await engine.createSession(),
    dialledByUs: true,
  );
  final linkB = PeerLink(
    conversationId: 'cB',
    channel: channelB,
    store: storeB,
    identity: testIdentity('b', alias: 'bob-owl-22', platform: 'macOS'),
    crypto: await engine.createSession(),
    dialledByUs: false,
  );

  await linkB.start(); // 인바운드 쪽이 먼저 리스닝
  await linkA.start(); // 아웃바운드 쪽이 다이얼하고 hello를 보냄
  await pumpEventQueue(times: 60);

  return (
    linkA: linkA,
    linkB: linkB,
    storeA: storeA,
    storeB: storeB,
    captured: captured,
  );
}

void main() {
  test('a captured encrypted frame is dropped when replayed', () async {
    final p = await _connectTappedPair();
    addTearDown(p.storeA.dispose);
    addTearDown(p.storeB.dispose);

    await p.linkA.sendText('meet at six', ttlSeconds: 0);
    await pumpEventQueue(times: 60);
    expect(_chat(p.storeB, 'cB'), hasLength(1));

    // 캡처한 프레임(방금 보낸 enc 프레임)을 그대로 다시 주입: 공격자가
    // 전선에서 프레임 하나를 재전송하는 상황을 흉내냄
    p.linkA.channel.sink.add(p.captured.last);
    await pumpEventQueue(times: 60);

    expect(
      _chat(p.storeB, 'cB'),
      hasLength(1),
      reason: 'replayed frame must not add a second message',
    );
  });

  test(
    'a stale (lower-seq) frame is ignored after a newer one already arrived',
    () async {
      final p = await _connectTappedPair();
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      await p.linkA.sendText('first', ttlSeconds: 0);
      await pumpEventQueue(times: 60);
      final firstFrame = p.captured.last;

      await p.linkA.sendText('second', ttlSeconds: 0);
      await pumpEventQueue(times: 60);
      expect(_chat(p.storeB, 'cB'), hasLength(2));

      // seq가 더 낮은(먼저 캡처한) 프레임을 나중에 재주입: 역행이라 버려짐
      p.linkA.channel.sink.add(firstFrame);
      await pumpEventQueue(times: 60);

      expect(
        _chat(p.storeB, 'cB'),
        hasLength(2),
        reason: 'a stale/regressed seq must not be re-applied',
      );
    },
  );

  test(
    'a frame dropped on the wire ends the link instead of passing',
    () async {
      var dropNextEnc = false;
      final p = await _connectTappedPair(
        drop: (raw) {
          if (!dropNextEnc || !raw.contains('"t":"enc"')) return false;
          dropNextEnc = false;
          return true;
        },
      );
      addTearDown(p.storeA.dispose);
      addTearDown(p.storeB.dispose);

      await p.linkA.sendText('one', ttlSeconds: 0);
      await pumpEventQueue(times: 60);
      dropNextEnc = true;
      await p.linkA.sendText('two', ttlSeconds: 0);
      await pumpEventQueue(times: 60);
      await p.linkA.sendText('three', ttlSeconds: 0);
      await pumpEventQueue(times: 60);

      expect(_chat(p.storeB, 'cB').map((m) => m.text), ['one']);
      expect(
        p.linkB.isClosed,
        isTrue,
        reason: 'a gap in seq means frames went missing',
      );
    },
  );
}
