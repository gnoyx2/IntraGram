part of '../app_providers.dart';

// 앱 수명 동안 같은 인스턴스를 유지함 (alias·패닉 키 회전은 제자리 변경함). 화면은 identityAliasProvider를 watch해야 함
// main.dart가 키 있는 신원으로 override함. 기본값은 키 없는 테스트용이라 피어 링크를 맺을 수 없음
final appIdentityProvider = Provider<AppIdentity>(
  (ref) => AppIdentity.generate(),
);

final identityStoreProvider = Provider<IdentityStore>(
  (ref) => const IdentityStore(),
);

// legacy identity.json은 진짜 PIN unlock(또는 PIN 없음)일 때만 읽음
// decoy 세션이 실제 세션의 기기 이름을 못 보게 함
final _savedAliasProvider = FutureProvider<String?>((ref) async {
  final access = ref.watch(vaultAccessProvider);
  if (access is! VaultOpen) return null;
  if (!ref.read(vaultAccessProvider.notifier).canReadLegacyIdentity) {
    return null;
  }
  return ref.watch(identityStoreProvider).loadAlias();
});

// 제자리 변경은 Riverpod가 감지하지 못하므로 alias 변화를 위젯 리빌드로 전달함
final identityAliasProvider = NotifierProvider<IdentityAliasNotifier, String>(
  IdentityAliasNotifier.new,
);

class IdentityAliasNotifier extends Notifier<String> {
  @override
  String build() {
    final identity = ref.read(appIdentityProvider);
    // 값이 늦게 와도 notifier가 재생성되지 않게 watch 대신 listen을 씀. 보관소 savedAlias와 identity.json을 둘 다 봄
    ref.listen<VaultSettings>(vaultSettingsProvider, (_, next) {
      final saved = next.savedAlias;
      if (saved != null && saved.isNotEmpty) _apply(identity, saved);
    }, fireImmediately: true);
    ref.listen<AsyncValue<String?>>(_savedAliasProvider, (_, next) {
      final saved = next.value;
      if (saved != null && saved.isNotEmpty) _apply(identity, saved);
    }, fireImmediately: true);
    return identity.alias;
  }

  // 저장된 이름이 늦게 올 수 있어서 mDNS 광고도 다시 내보냄 (안 그러면 다른 기기가 이전 랜덤 이름을 봄). 광고 전이면 무시됨
  void _apply(AppIdentity identity, String alias) {
    identity.rename(alias);
    state = alias;
    unawaited(
      ref.read(discoveryControllerProvider.notifier).restartBroadcast(),
    );
  }

  // 연결된 피어에게도 새 이름을 알림 (hello는 핸드셰이크 때 한 번만 보냄)
  // vault가 켜져 있으면 vault에, 아니면 identity.json에 저장함. duress 세션은 디스크에 안 씀
  Future<void> rename(String alias, {required bool save}) async {
    _apply(ref.read(appIdentityProvider), alias);
    ref.read(linkRegistryProvider).broadcastRename(alias);
    if (!save ||
        ref.read(vaultProvider).isDecoyMode ||
        !ref.read(vaultAccessProvider.notifier).canWriteArchive) {
      return;
    }
    if (ref.read(vaultSettingsProvider).enabled) {
      await ref.read(vaultSettingsProvider.notifier).setSavedAlias(alias);
    } else {
      await ref.read(identityStoreProvider).saveAlias(alias);
    }
  }

  // duress 세션이면 저장 파일은 그대로 두고 RAM의 표시 이름만 바꿈
  Future<void> resetToRandom() async {
    await rename(AppIdentity.randomAlias(), save: false);
    if (ref.read(vaultProvider).isDecoyMode ||
        !ref.read(vaultAccessProvider.notifier).canWriteArchive) {
      return;
    }
    if (ref.read(vaultSettingsProvider).enabled) {
      await ref.read(vaultSettingsProvider.notifier).setSavedAlias(null);
    } else {
      await ref.read(identityStoreProvider).clear();
    }
  }
}

final cryptoEngineProvider = Provider<CryptoEngine>((ref) => CryptoEngine());

final linkRegistryProvider = Provider<LinkRegistry>((ref) {
  final store = ref.watch(inMemoryStoreProvider);
  final registry = LinkRegistry(
    store: store,
    crypto: ref.watch(cryptoEngineProvider),
    identity: ref.watch(appIdentityProvider),
  );
  // 와이프로 스토어에서 전송이 사라지면 취소 토큰/스테이징 source도 같이 정리함
  store.onTransferRemoved = registry.discardRemovedTransfer;
  ref.onDispose(registry.disposeAll);
  return registry;
});
