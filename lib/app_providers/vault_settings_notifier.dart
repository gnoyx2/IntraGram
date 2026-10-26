part of '../app_providers.dart';

class VaultSettingsNotifier extends Notifier<VaultSettings> {
  @override
  VaultSettings build() {
    // watch 대신 listen: watch면 게이트가 열리는 순간 notifier가 다시 만들어져서 호출자가 쥔 핸들이 죽음
    ref.listen<VaultAccessState>(vaultAccessProvider, (_, next) {
      // settings만 읽고 snapshot 내용은 안 건드림
      if (next is VaultOpen) state = next.settings;
    }, fireImmediately: true);
    return const VaultSettings();
  }

  // 실제 enabled: true -> false 전이일 때만 erase함. 이미 꺼진 상태에서 언어/배경 같은
  // RAM 전용 설정을 바꿀 때마다 erase하면 세션 PIN 등 RAM 상태까지 지워짐
  Future<void> _apply(VaultSettings next) async {
    final wasEnabled = state.enabled;
    final vault = ref.read(vaultProvider);
    final access = ref.read(vaultAccessProvider.notifier);
    if (!vault.isDecoyMode &&
        !access.canWriteArchive &&
        (next.enabled || wasEnabled)) {
      throw const VaultLockedException('locked archive is preserved');
    }
    state = next;
    if (next.enabled) {
      await vault.save(ref.read(inMemoryStoreProvider).toSnapshot(next));
    } else if (wasEnabled) {
      await vault.erase();
    }
  }

  // 끌 때 pinProtected도 같이 내림. 안 그러면 파일은 지워졌는데 플래그만 남아서
  // 다시 켤 때 PIN 없이 save()가 VaultLockedException을 던짐
  Future<void> setEnabled(bool value) => _apply(
    value
        ? state.copyWith(enabled: true)
        : state.copyWith(enabled: false, pinProtected: false),
  );

  // enabled와 상관없이 파일을 지움: startFresh로 잠긴 아카이브를 남겨 둔 세션이나 duress 세션에서도 진짜 파일까지 지움
  Future<void> eraseForPanic() async {
    state = state.copyWith(enabled: false, pinProtected: false);
    await ref.read(vaultProvider).erase();
  }

  Future<void> setAutoLockMinutes(int value) =>
      _apply(state.copyWith(autoLockMinutes: value));

  Future<void> setKeepMessages(bool value) =>
      _apply(state.copyWith(keepMessages: value));

  Future<void> setKeepTransfers(bool value) =>
      _apply(state.copyWith(keepTransfers: value));

  Future<void> setStayConnected(bool value) =>
      _apply(state.copyWith(stayConnectedInBackground: value));

  // 스토어 미러도 즉시 갱신 (링크 레이어가 인바운드 hello에서 읽음)
  Future<void> setOnlyChatsIStart(bool value) {
    ref.read(inMemoryStoreProvider).onlyChatsIStart = value;
    return _apply(state.copyWith(onlyChatsIStart: value));
  }

  Future<void> setTextScale(double value) =>
      _apply(state.copyWith(textScale: value));

  // 'en' / 'ko' / null(OS 로케일)
  Future<void> setLangOverride(String? code) =>
      _apply(state.copyWith(langOverride: code));

  // 스토어 미러도 즉시 갱신 (링크 레이어가 거기서 읽음)
  Future<void> setLargeMessageMode(LargeMessageMode mode) {
    ref.read(inMemoryStoreProvider).largeMessageMode = mode;
    return _apply(state.copyWith(largeMessageMode: mode));
  }

  // pin 있으면 세션 PIN으로 등록 후 다음 저장부터 봉인, null이면 PIN을 잊고 평문 복귀
  // duress PIN과 같으면 false (그대로 두면 진짜 PIN으로 열 때 duress가 죽음)
  Future<bool> setPinProtected({required bool value, String? pin}) async {
    if (!state.enabled) return true;
    final vault = ref.read(vaultProvider);
    final next = value ? pin : null;
    if (next != null && await vault.isDecoyPin(next)) return false;
    if (!vault.setPin(next)) return false;
    await _apply(state.copyWith(pinProtected: value));
    return true;
  }

  // duress PIN: 이 PIN으로 열면 빈 세션이 뜨고 변경은 저장 안 됨
  // 진짜 PIN과 같으면 false로 거부함
  Future<bool> setDecoyPin({String? pin}) async {
    if (!state.enabled || !state.pinProtected) return false;
    final vault = ref.read(vaultProvider);
    if (!vault.setDecoyPin(pin)) return false;
    await vault.save(ref.read(inMemoryStoreProvider).toSnapshot(state));
    return true;
  }

  // 보관소 켜짐이면 vault 스냅샷의 일부라 decoy/erase 격리를 나머지와 똑같이 받음
  // 꺼져 있으면 no-op (vault 독립 경로인 IdentityStore가 대신 씀)
  Future<void> setSavedAlias(String? alias) {
    if (!state.enabled) return Future<void>.value();
    return _apply(state.copyWith(savedAlias: alias));
  }
}
