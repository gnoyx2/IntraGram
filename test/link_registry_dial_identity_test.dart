import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 탐지된 피어를 다이얼할 때(연결·초대)는 광고된 peerId를 가진 쪽임이 증명돼야 링크가 성립하고, 수동 IP
// 연결은 진짜 peerId를 몰라서 상대가 밝힌(증명한) peerId를 그대로 받음
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

  PeerDevice advertised(String peerId) => PeerDevice(
    peerId: peerId,
    alias: 'peer',
    platform: 'test',
    host: '192.168.1.20',
    port: 7890,
    seenAt: DateTime(2026),
  );

  // connect가 다이얼하는 상대를 정직하게 증명하는 스크립트 리스너(b)로 두고 대화를 돌려줌
  Future<Conversation> dial(Future<String> Function() connect) async {
    final wire = StreamChannelController<dynamic>();
    registry.debugDial = (_) async => wire.local;
    final listener = await ScriptedPeer.create(
      testIdentity('b', alias: 'listener'),
      wire.foreign,
    );
    final id = await connect();
    await pumpEventQueue(times: 30);
    listener.sendHello(signature: await listener.proof(asDialer: false));
    await pumpEventQueue(times: 80);
    return store.conversation(id)!;
  }

  test(
    'a discovered peer that proves its advertised peerId connects',
    () async {
      final conversation = await dial(
        () => registry.connectToPeer(advertised(testPeerId('b'))),
      );
      expect(conversation.secure, isTrue);
      expect(conversation.peerId, testPeerId('b'));
    },
  );

  test(
    'a discovered peer that cannot prove the advertised id is refused',
    () async {
      // 광고는 c의 peerId인데 그 주소에서 나온 건 (정직한) b
      final conversation = await dial(
        () => registry.connectToPeer(advertised(testPeerId('c'))),
      );
      expect(conversation.secure, isFalse);
      expect(conversation.online, isFalse, reason: 'the link was closed');
      // 대화는 광고된 상대(c)에게 묶인 채 남음: 다시 연결하거나 같은 주소의 다른 링크가 끼어들어도
      // c가 아니면 이어붙지 않음(link_registry_pre_proof_test)
      expect(conversation.peerId, testPeerId('c'));
    },
  );

  test('a manual connection takes the peerId the peer proves', () async {
    final conversation = await dial(
      () => registry.connectManual(host: '192.168.1.20', port: 7890),
    );
    expect(conversation.secure, isTrue);
    expect(conversation.peerId, testPeerId('b'));
  });

  // 기기 코드 QR은 화면에서 읽은 peerId를 실어 와서, 그 주소에 다른 기기가 있으면 연결이 안 됨
  test('a scanned device code connects only to the device it shows', () async {
    final pinned = await dial(
      () => registry.connectManual(
        host: '192.168.1.20',
        port: 7890,
        expectedPeerId: testPeerId('b'),
      ),
    );
    expect(pinned.secure, isTrue);

    final other = await dial(
      () => registry.connectManual(
        host: '192.168.1.20',
        port: 7890,
        expectedPeerId: testPeerId('c'),
      ),
    );
    expect(other.secure, isFalse, reason: 'b answered a code that shows c');
    expect(other.peerId, testPeerId('c'));
  });
}
