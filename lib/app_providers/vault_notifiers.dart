part of '../app_providers.dart';

// '아직 모름'과 '잠금 없음'을 구분하려는 sealed 타입
// 뭉뚱그리면 로딩 중 Home이 한 프레임 잘못 뜸
sealed class VaultAccessState {
  const VaultAccessState();
}

final class VaultChecking extends VaultAccessState {
  const VaultChecking();
}

final class VaultLocked extends VaultAccessState {
  const VaultLocked();
}

// 내용은 안 들고 게이트 메타데이터만 가짐 (스냅샷은 takeSnapshot으로 한 번만 소비함)
final class VaultOpen extends VaultAccessState {
  const VaultOpen({required this.settings, required this.archivePreserved});

  final VaultSettings settings;

  // 이 세션이 만들지 않은 암호화/평문 아카이브가 디스크에 있으면 true임
  // 설정 변경이나 vault 토글로 그 파일을 조용히 덮어쓰지 않게 막는 신호임
  final bool archivePreserved;
}

class VaultAccessNotifier extends Notifier<VaultAccessState> {
  int _relockGeneration = 0;
  // takeSnapshot이 소비하면 즉시 null이 됨. VaultOpen은 스냅샷을 들고 있지 않아서
  // provider 재생성 뒤 fireImmediately listener가 지운 내용을 재hydrate하지 못함
  VaultSnapshot? _pendingSnapshot;

  // 진짜 PIN unlock 또는 PIN 보호 없음일 때만 true
  // decoy/locked/startFresh는 인증 안 된 진입이라 항상 false
  bool _legacyIdentityReadable = false;
  bool get canReadLegacyIdentity => _legacyIdentityReadable;

  // 읽기 권한이 확인된 세션만 다시 씀. startFresh는 잠긴 파일을 보존하고,
  // duress는 decoy no-op 경로로만 편집함
  bool get canWriteArchive => _legacyIdentityReadable;

  @override
  VaultAccessState build() {
    unawaited(_checkLocked());
    return const VaultChecking();
  }

  Future<void> _checkLocked() async {
    final vault = ref.read(vaultProvider);
    try {
      if (await vault.isEncrypted()) {
        if (ref.mounted) state = const VaultLocked();
        return;
      }
      final snapshot = await vault.load();
      _legacyIdentityReadable = true;
      _open(snapshot, archivePreserved: snapshot != null);
    } on FileSystemException {
      // 확인~판독 사이 디스크 실패 시 잠금을 유지함. 빈 세션으로 열면 기존 파일을 덮을 수 있음
      if (ref.mounted) state = const VaultLocked();
    }
  }

  // 실패 횟수는 RAM에만 있어 앱을 다시 켜면 0부터임. 파일 자체를 빼 가는
  // 오프라인 대입은 PIN KDF 비용이 막고, 이건 화면에서 연달아 찍어 보는 것만 늦춤
  int _pinFailures = 0;
  bool _unlocking = false;

  // 틀릴 때마다 응답을 pinRetryDelay만큼 늦추고 그동안 다른 시도는 거절함
  Future<bool> unlock(String pin) async {
    if (_unlocking) return false;
    _unlocking = true;
    try {
      final ok = await _unlock(pin);
      if (ok) {
        _pinFailures = 0;
      } else {
        await Future<void>.delayed(pinRetryDelay(_pinFailures++));
      }
      return ok;
    } finally {
      _unlocking = false;
    }
  }

  // unlock이 돌려준 스냅샷을 그대로 씀. load()를 다시 부르면 디스크 읽기와 PBKDF2가 중복됨
  Future<bool> _unlock(String pin) async {
    final vault = ref.read(vaultProvider);
    final snap = await vault.unlock(pin);
    if (snap == null) return false;
    // 옛 dchk 파일이면 바로 v2로 다시 씀. 실패해도 다음 저장이 또 시도하니 잠금 해제는 막지 않음
    if (vault.needsRewrite) {
      unawaited(vault.save(snap).catchError((Object _) {}));
    }
    // duress PIN이면 isDecoyMode가 true라 legacy 이름 읽기 차단됨
    _legacyIdentityReadable = !vault.isDecoyMode;
    _open(snap, archivePreserved: true);
    return true;
  }

  // 자동 재잠금 1단계: 화면부터 열린 상태를 내리고 디바운스 저장을 막음 (canWriteArchive가 false)
  int beginRelock() {
    _legacyIdentityReadable = false;
    _pendingSnapshot = null;
    state = const VaultChecking();
    return ++_relockGeneration;
  }

  // 2단계: 링크가 다 닫힌 뒤의 최종 상태를 봉인하고 세션 키를 폐기함
  // 저장이 실패해도 잠금은 걸림 (실패는 호출부로 올라감)
  Future<void> finishRelock(VaultSnapshot snapshot, int generation) async {
    final vault = ref.read(vaultProvider);
    try {
      await vault.save(snapshot);
    } finally {
      completeRelock(generation);
    }
  }

  // 저장이 시간 초과되어도 잠금을 완료함. 뒤늦게 끝난 저장은 열린 새 세션을 잠그지 못함.
  void completeRelock(int generation) {
    if (!ref.mounted ||
        generation != _relockGeneration ||
        state is! VaultChecking) {
      return;
    }
    _relockGeneration++;
    ref.read(vaultProvider).lock();
    state = const VaultLocked();
  }

  // 기존 아카이브를 덮거나 지우지 않고 빈 세션으로 진행함
  // PIN 증명 없는 진입이라 legacy 이름도 안 읽음
  void startFresh() {
    _legacyIdentityReadable = false;
    _open(null, archivePreserved: true);
  }

  void _open(VaultSnapshot? snapshot, {required bool archivePreserved}) {
    _pendingSnapshot = snapshot;
    if (ref.mounted) {
      state = VaultOpen(
        settings: snapshot?.settings ?? const VaultSettings(),
        archivePreserved: archivePreserved,
      );
    }
  }

  // 읽는 즉시 null로 비움. provider가 재생성돼도 같은 스냅샷을 또 hydrate 못 하게 함
  VaultSnapshot? takeSnapshot() {
    final snap = _pendingSnapshot;
    _pendingSnapshot = null;
    return snap;
  }

  // panic/end-session에서 미소비 스냅샷 참조도 제거함
  void clearPendingSnapshot() {
    _pendingSnapshot = null;
    ref.read(vaultProvider).lock();
  }
}
