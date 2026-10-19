import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'test_identities.dart';

Conversation conv(String id, String peerAlias) => Conversation(
  id: id,
  peerAlias: peerAlias,
  peerPlatform: 'test',
  transport: PeerTransport.app,
  startedAt: DateTime(2026, 1, 1),
  online: true,
);

// 핸드셰이크가 각 store에 로컬 "Encrypted…" 시스템 줄을
// 넣는데, 이 assertion들은 채팅 트래픽 대상이라 그 줄을 걸러냄
List<EphemeralMessage> chat(InMemoryStore store, String id) =>
    store.messages(id).where((m) => m.kind != MessageKind.system).toList();

// 인메모리 duplex 채널로 두 PeerLink를 이음
Future<
  ({PeerLink linkA, PeerLink linkB, InMemoryStore storeA, InMemoryStore storeB})
>
connectedPair({int? localPortA, int? remotePortB}) async {
  final engine = CryptoEngine();
  final wire = StreamChannelController<dynamic>();

  final storeA = InMemoryStore()..upsertConversation(conv('cA', 'bob-owl-22'));
  final storeB = InMemoryStore()
    ..upsertConversation(
      conv('cB', 'alice-fox-11').copyWith(peerPort: remotePortB),
    );

  final linkA = PeerLink(
    conversationId: 'cA',
    channel: wire.local,
    store: storeA,
    identity: testIdentity('a', alias: 'alice-fox-11', platform: 'Linux'),
    crypto: await engine.createSession(),
    localPort: localPortA,
    dialledByUs: true,
  );
  final linkB = PeerLink(
    conversationId: 'cB',
    channel: wire.foreign,
    store: storeB,
    identity: testIdentity('b', alias: 'bob-owl-22', platform: 'macOS'),
    crypto: await engine.createSession(),
    remotePort: remotePortB,
    dialledByUs: false,
  );

  await linkB.start(); // 인바운드 쪽이 먼저 리스닝
  await linkA.start(); // 아웃바운드 쪽이 다이얼하고 hello를 보냄
  await pumpEventQueue(times: 60);

  return (linkA: linkA, linkB: linkB, storeA: storeA, storeB: storeB);
}
