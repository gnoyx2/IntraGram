import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart' show conv;
import 'support/scripted_inbound.dart';
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 신원이 증명되기 전의 링크는 아무것도 얻지 못함: 가짜 mDNS 광고(공격자 M이 피해자 b의 peerId를 자기
// 주소에 광고)로 사용자가 M을 눌러도, 그 주소에서 미리 열어 둔 인바운드 소켓이 다이얼 대화·방·전송에
// 끼어들지 못하고, 증명 전엔 프레임도 안 나감
void main() {
  const attackerHost = '192.168.1.20';
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

  // M이 b의 peerId를 자기 주소에 광고한 가짜 탐지 결과
  PeerDevice spoofed() => PeerDevice(
    peerId: testPeerId('b'),
    alias: 'victim',
    platform: 'test',
    host: attackerHost,
    port: 7890,
    seenAt: DateTime(2026),
  );

  // 응답이 없는 다이얼(M의 서버는 hello를 안 보냄). 다이얼 횟수를 셈
  int Function() silentDial() {
    var dials = 0;
    registry.debugDial = (_) async {
      dials++;
      final wire = StreamChannelController<dynamic>();
      wire.foreign.stream.listen((_) {});
      return wire.local;
    };
    return () => dials;
  }

  // hello를 안 보내고 열려만 있는 인바운드 소켓(미인증 placeholder 대화 하나를 만듦)
  Future<String> idleInbound(String host) async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: host,
      remotePort: 5000,
    );
    return store.conversations.last.id;
  }

  test('a dial that expects b is not taken over by another peer', () async {
    silentDial();
    final dialled = await registry.connectToPeer(spoofed());

    await connectScriptedInbound(
      registry,
      host: attackerHost,
      identity: testIdentity('c'),
    );

    final conversation = store.conversation(dialled)!;
    expect(conversation.secure, isFalse);
    expect(conversation.peerId, isNot(testPeerId('c')));
    expect(registry.linkFor(dialled)?.remotePeerId, isNull);
  });

  test('a manual dial is not taken over by an inbound link either', () async {
    silentDial();
    final dialled = await registry.connectManual(
      host: attackerHost,
      port: 7890,
    );

    await connectScriptedInbound(
      registry,
      host: attackerHost,
      identity: testIdentity('c'),
    );

    expect(store.conversation(dialled)!.secure, isFalse);
    expect(registry.linkFor(dialled)?.remotePeerId, isNull);
  });

  test('a pending inbound socket is never reused for a dial', () async {
    final placeholder = await idleInbound(attackerHost);
    final dials = silentDial();

    final dialled = await registry.connectToPeer(spoofed());

    expect(dials(), 1, reason: 'dialled with the expected peerId');
    expect(dialled, isNot(placeholder));
  });

  test('an invite never puts an unproven link into the room', () async {
    await idleInbound(attackerHost);
    silentDial();

    await registry.inviteToRoom(spoofed());
    await pumpEventQueue();

    expect(registry.appRoomId, isNull);
    expect(store.conversations.any((c) => c.isRoom), isFalse);
  });

  test('an invite waits for the proof of a dial already in progress', () async {
    silentDial();
    await registry.connectToPeer(spoofed());

    await registry.inviteToRoom(spoofed());
    await pumpEventQueue();

    expect(registry.appRoomId, isNull);
  });

  test('adding people never promotes an unproven conversation', () async {
    final placeholder = await idleInbound(attackerHost);

    await registry.addPeersToRoom(placeholder, const []);

    expect(registry.appRoomId, isNull);
    expect(store.conversation(placeholder)!.isRoom, isFalse);
  });

  test('a refused hello never wipes a room conversation', () async {
    final wire = StreamChannelController<dynamic>();
    final roomStore = InMemoryStore()
      ..upsertConversation(
        Conversation(
          id: 'room',
          peerAlias: 'Room',
          peerPlatform: 'Room',
          transport: PeerTransport.app,
          startedAt: DateTime(2026),
          online: true,
          isRoom: true,
        ),
      );
    addTearDown(roomStore.dispose);
    final link = PeerLink(
      conversationId: 'room',
      channel: wire.foreign,
      store: roomStore,
      identity: testIdentity('b', alias: 'host'),
      crypto: await CryptoEngine().createSession(),
    );
    addTearDown(link.close);
    final impostor = await ScriptedPeer.create(testIdentity('a'), wire.local);
    await link.start();

    // 밝힌 peerId가 밝힌 키의 해시가 아님 → 거절
    impostor.sendDialerHello(
      peerId: testPeerId('a'),
      claimedKey: testIdentity('c').publicKey,
    );
    await pumpEventQueue(times: 60);

    expect(link.isClosed, isTrue);
    expect(roomStore.conversation('room'), isNotNull);
  });

  test('nothing is sent to a peer before it proves its identity', () async {
    final wire = StreamChannelController<dynamic>();
    final linkStore = InMemoryStore()..upsertConversation(conv('cB', 'peer'));
    addTearDown(linkStore.dispose);
    final link = PeerLink(
      conversationId: 'cB',
      channel: wire.foreign,
      store: linkStore,
      identity: testIdentity('b', alias: 'host'),
      crypto: await CryptoEngine().createSession(),
    );
    addTearDown(link.close);
    final peer = await ScriptedPeer.create(testIdentity('a'), wire.local);
    await link.start();
    peer.sendDialerHello();
    await pumpEventQueue(times: 60);
    await peer.completeHandshake(); // 키 합의는 끝났지만 증명은 아직

    await link.sendTyping(active: true);
    await pumpEventQueue(times: 60);
    expect(peer.frames.where((f) => f['t'] == 'enc'), isEmpty);

    peer.sendAuth(await peer.proof(asDialer: true));
    await pumpEventQueue(times: 60);
    expect(peer.frames.where((f) => f['t'] == 'enc'), hasLength(1));
  });

  test('an inbound socket that closes before hello leaves no tile', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {});
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.30',
      remotePort: 5000,
    );
    expect(store.conversations, hasLength(1));

    await wire.local.sink.close();
    await pumpEventQueue(times: 60);

    expect(store.conversations, isEmpty);
  });
}
