import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

class MemoryVault extends Vault {
  @override
  Future<bool> isEncrypted() async => false;
  @override
  Future<VaultSnapshot?> load({String? pin}) async => VaultSnapshot(
    settings: const VaultSettings(enabled: true),
    conversations: [
      Conversation(
        id: 'c',
        peerAlias: 'peer',
        peerPlatform: 'test',
        transport: PeerTransport.app,
        startedAt: DateTime.now(),
      ),
    ],
    messages: [
      EphemeralMessage(
        id: 'm',
        conversationId: 'c',
        direction: MessageDirection.incoming,
        kind: MessageKind.text,
        senderAlias: 'peer',
        createdAt: DateTime.now(),
        text: 'synthetic secret',
        delivery: DeliveryState.sent,
      ),
    ],
    transfers: [],
  );
  @override
  Future<void> save(VaultSnapshot snapshot) async {}
}

void main() {
  test('cleared store must not rehydrate an old retained snapshot', () async {
    final container = ProviderContainer(
      overrides: [vaultProvider.overrideWithValue(MemoryVault())],
    );
    addTearDown(container.dispose);
    final store = container.read(inMemoryStoreProvider);
    await pumpEventQueue(times: 30);
    expect(store.messages('c'), hasLength(1));
    store.stopPersisting();
    store.secureWipe();
    await store.drainDisposals();
    expect(store.messages('c'), isEmpty);
    container.invalidate(inMemoryStoreProvider);
    final next = container.read(inMemoryStoreProvider);
    expect(next.messages('c'), isEmpty);
  });
}
