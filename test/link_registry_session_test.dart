import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/link_registry_fixtures.dart';
import 'support/scripted_inbound.dart';
import 'support/test_identities.dart';

void main() {
  late InMemoryStore store;
  late Directory tmp;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    tmp = Directory.systemTemp.createTempSync('intragram_lr');
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => tmp.path,
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('acceptInbound registers a conversation and a live link', () async {
    final wire = StreamChannelController<dynamic>();
    wire.local.stream.listen((_) {}); // 피어 소켓 대역
    await registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.9',
      remotePort: 7890,
    );

    expect(store.conversations, hasLength(1));
    final id = store.conversations.single.id;
    expect(registry.linkFor(id), isNotNull);
    expect(registry.activeConversationIds, contains(id));
  });

  test('markVerified only flips to verified once both sides confirm', () async {
    store.upsertConversation(conv('c1'));
    expect(store.conversation('c1')!.verified, isFalse);

    registry.markVerified('c1', expectedSas: store.conversation('c1')!.sas);
    expect(store.conversation('c1')!.localVerified, isTrue);
    expect(
      store.conversation('c1')!.verified,
      isFalse,
      reason: 'peer has not confirmed their side yet',
    );

    store.setPeerVerified('c1'); // 피어가 자기 쪽에서 따로 확인
    expect(store.conversation('c1')!.verified, isTrue);
  });

  test(
    'markVerified rejects a stale expectedSas from a reconnected session',
    () async {
      store.upsertConversation(conv('c1'));
      store.setConversationSas('c1', 'AAA111');
      final expectedSas = store.conversation('c1')!.sas; // 다이얼로그가 캡처한 값

      store.setConversationSas('c1', 'BBB222'); // 그사이 재연결로 세션이 바뀜

      registry.markVerified('c1', expectedSas: expectedSas);
      expect(
        store.conversation('c1')!.localVerified,
        isFalse,
        reason: 'stale SAS confirmation must not apply to the new session',
      );

      registry.markVerified('c1', expectedSas: store.conversation('c1')!.sas);
      expect(store.conversation('c1')!.localVerified, isTrue);
    },
  );

  test(
    'markRoomMemberVerified rejects a stale expectedSas for that member',
    () async {
      store.upsertConversation(conv('r1').copyWith(isRoom: true));
      store.upsertRoomMember('r1', 'peer1', alias: 'bob', platform: 'test');
      store.setRoomMemberSas('r1', 'peer1', 'AAA111');
      final expectedSas = store.conversation('r1')!.members['peer1']!.sas;

      store.setRoomMemberSas('r1', 'peer1', 'BBB222'); // 재합류로 새 세션

      registry.markRoomMemberVerified('r1', 'peer1', expectedSas: expectedSas);
      expect(
        store.conversation('r1')!.members['peer1']!.localVerified,
        isFalse,
        reason: 'stale SAS confirmation must not apply to the new session',
      );

      registry.markRoomMemberVerified(
        'r1',
        'peer1',
        expectedSas: store.conversation('r1')!.members['peer1']!.sas,
      );
      expect(store.conversation('r1')!.members['peer1']!.localVerified, isTrue);
    },
  );

  test('inviteToRoom promotes an existing 1:1 link into a room', () async {
    await connectScriptedInbound(
      registry,
      host: '192.168.1.9',
      identity: testIdentity('b'),
    );
    final oldId = store.conversations.single.id;

    await registry.inviteToRoom(
      PeerDevice(
        peerId: testPeerId('b'),
        alias: 'bob',
        platform: 'macOS',
        host: '192.168.1.9',
        port: 7890,
        seenAt: DateTime(2026, 1, 1),
      ),
    );
    await pumpEventQueue();

    final roomId = registry.appRoomId;
    expect(roomId, isNotNull);
    expect(store.conversation(roomId!)!.isRoom, isTrue);
    expect(store.conversation(oldId), isNull, reason: 'provisional 1:1 wiped');
  });

  test(
    'addPeersToRoom promotes the current 1:1 in place, keeping history',
    () async {
      await connectScriptedInbound(
        registry,
        host: '192.168.1.9',
        identity: testIdentity('b'),
      );
      final convId = store.conversations.single.id;
      store.addMessage(
        EphemeralMessage(
          id: 'h1',
          conversationId: convId,
          direction: MessageDirection.incoming,
          kind: MessageKind.text,
          senderAlias: 'peer',
          createdAt: DateTime(2026, 1, 1),
          text: 'old history',
          delivery: DeliveryState.sent,
        ),
      );

      await registry.addPeersToRoom(convId, const []);
      await pumpEventQueue();

      expect(registry.appRoomId, convId, reason: 'promoted in place');
      expect(store.conversation(convId)!.isRoom, isTrue);
      expect(
        store.messages(convId).any((m) => m.text == 'old history'),
        isTrue,
      );
    },
  );

  test('connectManual rejects a public IP before opening a socket', () async {
    await expectLater(
      registry.connectManual(host: '8.8.8.8', port: 7890),
      throwsA(isA<SecurityException>()),
    );
  });

  test('connectManual rejects a non-literal host', () async {
    await expectLater(
      registry.connectManual(host: 'router.local', port: 7890),
      throwsA(isA<SecurityException>()),
    );
  });

  test('setAutoAcceptFiles only takes effect once the peer is verified', () {
    store.upsertConversation(conv('c1'));

    registry.setAutoAcceptFiles('c1', enabled: true);
    expect(
      store.conversation('c1')!.autoAcceptFiles,
      isFalse,
      reason: 'an unverified peer can never auto-accept',
    );

    registry.markVerified('c1', expectedSas: store.conversation('c1')!.sas);
    registry.setAutoAcceptFiles('c1', enabled: true);
    expect(
      store.conversation('c1')!.autoAcceptFiles,
      isFalse,
      reason: 'still pending — peer has not confirmed their side yet',
    );

    store.setPeerVerified('c1');
    registry.setAutoAcceptFiles('c1', enabled: true);
    expect(store.conversation('c1')!.autoAcceptFiles, isTrue);

    registry.setAutoAcceptFiles('c1', enabled: false);
    expect(store.conversation('c1')!.autoAcceptFiles, isFalse);
  });
}
