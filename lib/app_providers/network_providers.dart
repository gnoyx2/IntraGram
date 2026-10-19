part of '../app_providers.dart';

// 앱 평생 같은 객체 (alias만 제자리 변경). 화면은 identityAliasProvider를 watch할 것
// main.dart가 키 있는 신원으로 override함. 기본값은 키 없는 테스트용이라 피어 링크 불가
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

// 제자리 변경은 Riverpod가 감지 못 해서, alias 변화를 위젯 리렌더로 전달하는 신호용
final identityAliasProvider = NotifierProvider<IdentityAliasNotifier, String>(
  IdentityAliasNotifier.new,
);

class IdentityAliasNotifier extends Notifier<String> {
  @override
  String build() {
    final identity = ref.read(appIdentityProvider);
    // 값이 늦게 도착해도 notifier가 재생성되지 않게 watch 대신 listen으로 시드함
    // vault의 savedAlias와 legacy identity.json 둘 다 구독: 보관소 켜기 전엔
    // legacy가 적용되고, 켠 뒤 한 번 저장하면 vault 값이 적용됨
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

  // 저장된 이름이 디스크에서 늦게 로드될 수 있어서 mDNS 광고도 같이 갱신함
  // 안 하면 화면엔 새 이름인데 다른 기기는 옛 랜덤 alias(kind-crow-90 등)를 봄
  // restartBroadcast는 광고 전(서버 꺼짐)이면 조용히 무시하니 매번 불러도 안전
  void _apply(AppIdentity identity, String alias) {
    identity.rename(alias);
    state = alias;
    unawaited(
      ref.read(discoveryControllerProvider.notifier).restartBroadcast(),
    );
  }

  // 연결된 피어에게도 새 이름을 알림 (hello는 핸드셰이크 때 한 번뿐)
  // 저장은 vault 켜짐이면 vault 안, 아니면 identity.json. duress 세션은 디스크에 안 씀
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
  // 와이프로 스토어에서 전송이 사라지면 취소 토큰/스테이징 source도 같이 정리
  store.onTransferRemoved = registry.discardRemovedTransfer;
  ref.onDispose(registry.disposeAll);
  return registry;
});
