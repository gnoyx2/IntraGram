part of '../app_providers.dart';

final vaultProvider = Provider<Vault>((ref) {
  final vault = Vault();
  ref.onDispose(vault.dispose);
  return vault;
});

// 홈·서버·mDNS 시작·알림 이동은 VaultOpen 뒤에만 함 (확인 중에 홈이 잠깐 보였다 게이트로 바뀌는 깜빡임과 서버가 먼저 뜨는 걸 막음)
final vaultAccessProvider =
    NotifierProvider<VaultAccessNotifier, VaultAccessState>(
      VaultAccessNotifier.new,
    );

// 기본은 꺼짐 (완전 휘발)
final vaultSettingsProvider =
    NotifierProvider<VaultSettingsNotifier, VaultSettings>(
      VaultSettingsNotifier.new,
    );

// PIN을 틀린 횟수(0부터)별 다음 응답 지연: 1, 2, 4 ... 최대 60초
Duration pinRetryDelay(int failures) =>
    Duration(seconds: (1 << failures.clamp(0, 6)).clamp(1, 60));
