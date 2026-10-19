import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/link_registry_fixtures.dart' show identity;
import 'support/test_identities.dart';

// 차단한 기기는 어느 방향으로도 핸드셰이크를 못 마치고, '내가 연 대화만 받기'를 켜면 이번 세션에
// 대화한 적 없는 기기가 여는 연결을 거절함. 둘 다 RAM에만 있음 (신원 키가 실행마다 바뀜)

Conversation _known(String id, String peerId) =>
    conv(id, 'alice').copyWith(peerId: peerId, online: false);

void main() {
  late InMemoryStore store;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
  });

  // 'a' 기기가 이 registry로 다이얼해 옴. 링크가 증명까지 끝났는지 돌려줌
  Future<bool> dialFromA() async {
    final wire = StreamChannelController<dynamic>();
    final peerStore = InMemoryStore()..upsertConversation(conv('cA', 'host'));
    final peer = PeerLink(
      conversationId: 'cA',
      channel: wire.local,
      store: peerStore,
      identity: testIdentity('a', alias: 'alice', platform: 'test'),
      crypto: await CryptoEngine().createSession(),
      dialledByUs: true,
    );
    addTearDown(() async {
      await peer.close();
      peerStore.dispose();
    });
    await registry.acceptInbound(wire.foreign, remoteHost: '192.168.1.30');
    await peer.start();
    await pumpEventQueue(times: 80);
    return peer.isSecure;
  }

  test('a blocked device cannot open a chat again', () async {
    store.upsertConversation(_known('c1', testPeerId('a')));
    await registry.blockPeer('c1');
    expect(store.conversation('c1')!.blocked, isTrue);
    expect(registry.isBlocked(testPeerId('a')), isTrue);
    expect(
      store.messages('c1').last.systemEvent?.kind,
      SystemEventKind.peerBlocked,
    );

    expect(await dialFromA(), isFalse);
    expect(
      store.conversations.map((c) => c.id),
      ['c1'],
      reason: 'the refused socket left no placeholder chat',
    );

    registry.unblockPeer('c1');
    expect(store.conversation('c1')!.blocked, isFalse);
    expect(await dialFromA(), isTrue);
  });

  test('only chats I start refuses an unknown device and keeps a known '
      'one', () async {
    store.onlyChatsIStart = true;
    expect(await dialFromA(), isFalse);
    expect(store.conversations, isEmpty);

    store.upsertConversation(_known('c1', testPeerId('a')));
    expect(await dialFromA(), isTrue);
  });

  test('only chats I start is kept with the other settings', () {
    final back = VaultSettings.fromJson(
      const VaultSettings(onlyChatsIStart: true).toJson(),
    );
    expect(back.onlyChatsIStart, isTrue);
    expect(VaultSettings.fromJson(const {}).onlyChatsIStart, isFalse);
  });
}
