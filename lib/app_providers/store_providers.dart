part of '../app_providers.dart';

// 보관 켜짐이면 시작 시 vault에서 채우고, 변경분은 1초 디바운스로 저장함
final inMemoryStoreProvider = Provider<InMemoryStore>((ref) {
  final store = InMemoryStore();
  ref.onDispose(store.dispose);

  final vault = ref.watch(vaultProvider);
  store.onPersistableChange = () {
    final settings = ref.read(vaultSettingsProvider);
    if (settings.enabled &&
        ref.read(vaultAccessProvider.notifier).canWriteArchive) {
      unawaited(vault.save(store.toSnapshot(settings)));
    }
  };

  ref.listen<VaultAccessState>(vaultAccessProvider, (_, next) {
    if (next is! VaultOpen) return;
    // settings는 metadata라 보관소 on/off와 무관하게 항상 적용됨
    store.largeMessageMode = next.settings.largeMessageMode;
    store.onlyChatsIStart = next.settings.onlyChatsIStart;
    // 스냅샷은 한 번만 소비함. invalidate로 재빌드돼도 null이라 재hydrate 안 됨
    final snap = ref.read(vaultAccessProvider.notifier).takeSnapshot();
    if (snap != null && next.settings.enabled) store.hydrate(snap);
  }, fireImmediately: true);

  return store;
});

final conversationsProvider = StreamProvider<List<Conversation>>(
  (ref) => ref.watch(inMemoryStoreProvider).watchConversations(),
);

final conversationProvider = Provider.family<Conversation?, String>((ref, id) {
  final list = ref.watch(conversationsProvider).value ?? const <Conversation>[];
  return list.firstWhereOrNull((c) => c.id == id);
});

final roomMessagesProvider =
    StreamProvider.family<List<EphemeralMessage>, String>(
      (ref, id) => ref.watch(inMemoryStoreProvider).watchRoom(id),
    );

// 원본이 소각·삭제되면 null을 반환함 (UI는 삭제된 메시지로 보여 줌)
// 방 스트림은 갱신 신호로만 쓰고 조회는 스토어 인덱스로 O(1)에 처리함. 값이 같으면(==) 구독자에 안 알림
final messageByIdProvider =
    Provider.family<
      EphemeralMessage?,
      ({String conversationId, String messageId})
    >((ref, key) {
      ref.watch(roomMessagesProvider(key.conversationId));
      final message = ref
          .watch(inMemoryStoreProvider)
          .messageById(key.messageId);
      return message?.conversationId == key.conversationId ? message : null;
    });

final transfersProvider = StreamProvider<List<FileTransfer>>(
  (ref) => ref.watch(inMemoryStoreProvider).watchTransfers(),
);

final transferProvider = Provider.family<FileTransfer?, String>((ref, id) {
  final list = ref.watch(transfersProvider).value ?? const <FileTransfer>[];
  return list.firstWhereOrNull((t) => t.id == id);
});

// '전부 수락·거절' 버튼이 offered 상태인 형제 수를 셀 때 씀
final transfersInBatchProvider =
    Provider.family<
      List<FileTransfer>,
      ({String conversationId, String batchId})
    >((ref, key) {
      final list = ref.watch(transfersProvider).value ?? const <FileTransfer>[];
      return list
          .where(
            (t) =>
                t.conversationId == key.conversationId &&
                t.batchId == key.batchId,
          )
          .toList();
    });
