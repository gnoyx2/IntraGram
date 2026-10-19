import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/scripted_inbound.dart';
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 호스트가 방을 끝낸 뒤에야 핸드셰이크를 마친 초대 상대가 끝난 방을 새로 되살리지 않음
void main() {
  late InMemoryStore store;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: testIdentity('a', alias: 'me', platform: 'test'),
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
    });
  });

  PeerDevice device(String letter, String host) => PeerDevice(
    peerId: testPeerId(letter),
    alias: letter,
    platform: 'test',
    host: host,
    port: 7890,
    seenAt: DateTime(2026),
  );

  test('an invite that proves itself after the room ended stays out', () async {
    await connectScriptedInbound(
      registry,
      host: '192.168.1.9',
      identity: testIdentity('b'),
    );
    await registry.inviteToRoom(device('b', '192.168.1.9'));
    await pumpEventQueue();
    final roomId = registry.appRoomId!;

    final wire = StreamChannelController<dynamic>();
    registry.debugDial = (_) async => wire.local;
    final late = await ScriptedPeer.create(testIdentity('c'), wire.foreign);
    await registry.inviteToRoom(device('c', '192.168.1.20'));
    await pumpEventQueue(times: 30);

    await registry.disconnect(roomId);
    store.wipeConversation(roomId);
    late.sendHello(signature: await late.proof(asDialer: false));
    await pumpEventQueue(times: 80);

    expect(registry.appRoomId, isNull);
    expect(store.conversations.where((c) => c.isRoom), isEmpty);
  });
}
