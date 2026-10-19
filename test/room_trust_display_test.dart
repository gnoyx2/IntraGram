import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

import 'support/handshake_pair.dart';
import 'support/link_registry_fixtures.dart' show identity;
import 'support/scripted_inbound.dart';
import 'support/test_identities.dart';
import 'ui/_harness.dart' as ui;

// 1:1에서 맞춘 코드는 방으로 바뀌어도 같은 세션이라 양쪽 다 멤버 슬롯으로 넘어가고, 대화 단위 검증은
// 비워서 홈 목록이 방을 1:1처럼 "검증됨"으로 보이지 않게 함 (방의 초록은 멤버 전원일 때만)
void main() {
  test('the host moves checked 1:1 trust into the member slot', () async {
    final store = InMemoryStore();
    final tmp = Directory.systemTemp.createTempSync('intragram_trust');
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => tmp.path,
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
      tmp.deleteSync(recursive: true);
    });
    await connectScriptedInbound(
      registry,
      host: '192.168.1.9',
      identity: testIdentity('b'),
    );
    final id = store.conversations.single.id;
    store.updateConversation(
      id,
      (c) => c.copyWith(localVerified: true, peerVerified: true),
    );

    await registry.addPeersToRoom(id, const []);
    await pumpEventQueue();

    final room = store.conversation(id)!;
    expect(room.members[testPeerId('b')]!.verified, isTrue);
    expect([room.localVerified, room.peerVerified], [false, false]);
  });

  test('a member keeps the host code it already checked', () async {
    final p = await connectedPair();
    addTearDown(() async {
      await p.linkA.close();
      await p.linkB.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });
    p.storeB.updateConversation(
      'cB',
      (c) => c.copyWith(localVerified: true, peerVerified: true),
    );

    await p.linkA.sendRoomJoin(2, peers: const []);
    await pumpEventQueue(times: 40);

    final room = p.storeB.conversation('cB')!;
    expect(room.isRoom, isTrue);
    expect(room.members.values.single.verified, isTrue);
    expect([room.localVerified, room.peerVerified], [false, false]);
  });

  testWidgets('a room tile shows the relay icon, green only when every '
      'member is checked', (tester) async {
    Conversation room(bool checked) => ui
        .conv('r1', secure: true, verified: true)
        .copyWith(
          isRoom: true,
          memberCount: 3,
          members: {
            'm1': const RoomMember(
              alias: 'a',
              localVerified: true,
              peerVerified: true,
            ),
            'm2': RoomMember(
              alias: 'b',
              localVerified: checked,
              peerVerified: checked,
            ),
          },
        );
    for (final checked in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ConversationTile(
              conversation: room(checked),
              onTap: () {},
              onMenu: ([_]) {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.gpp_good), findsNothing);
      final hub = tester.widget<Icon>(find.byIcon(Icons.hub_outlined));
      expect(
        hub.color,
        checked ? ChatColors.light.online : ChatColors.light.burn,
      );
      expect(find.textContaining('host relay'), findsOneWidget);
    }
  });
}
