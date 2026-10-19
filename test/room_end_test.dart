import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import 'support/transfer_rig.dart';

// 호스트가 자기 방을 "대화 종료"하면 멤버 연결도 끝나야 하고, 그 뒤 무엇이 와도 Vault에 안 남아야 함
void main() {
  EphemeralMessage orphan() => EphemeralMessage(
    id: 'ghost',
    conversationId: 'gone',
    direction: MessageDirection.incoming,
    kind: MessageKind.text,
    senderAlias: 'x',
    createdAt: DateTime(2026),
    text: 'orphan',
    delivery: DeliveryState.delivered,
  );

  test('ending a hosted room closes every member link', () async {
    final rig = await TransferRig.create(members: 3);
    final roomId = await rig.formRoom();
    expect(rig.remotes.every((m) => !m.isClosed), isTrue);

    await rig.registry.disconnect(roomId);
    rig.store.wipeConversation(roomId);
    await pumpEventQueue(times: 200);

    expect(rig.remotes.every((m) => m.isClosed), isTrue);
    expect(rig.registry.appRoomId, isNull);
  });

  test('nothing from an ended room reaches the vault snapshot', () async {
    final rig = await TransferRig.create(members: 3);
    final roomId = await rig.formRoom();
    await rig.registry.disconnect(roomId);
    rig.store.wipeConversation(roomId);
    await pumpEventQueue(times: 100);

    // 링크가 남아 있었다면 이 메시지가 지운 방 id로 다시 쌓였음
    await rig.remotes[1].sendText('after the host ended', ttlSeconds: 0);
    await pumpEventQueue(times: 200);

    final snapshot = rig.store.toSnapshot(const VaultSettings(enabled: true));
    expect(snapshot.messages, isEmpty);
    expect(snapshot.toJson().toString(), isNot(contains('after the host')));
  });

  test('a message without a conversation is dropped on arrival', () {
    final store = InMemoryStore();
    addTearDown(store.dispose);
    store.addMessage(orphan());
    expect(store.messages('gone'), isEmpty);
    expect(
      store.toSnapshot(const VaultSettings(enabled: true)).messages,
      isEmpty,
    );
  });

  test('a vault message without its conversation is not restored', () {
    final store = InMemoryStore();
    addTearDown(store.dispose);
    store.hydrate(
      VaultSnapshot(
        settings: const VaultSettings(enabled: true),
        conversations: const <Conversation>[],
        messages: [orphan()],
        transfers: const <FileTransfer>[],
      ),
    );
    expect(store.messages('gone'), isEmpty);
  });
}
