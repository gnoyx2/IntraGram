part of '../app_providers.dart';

final vaultProvider = Provider<Vault>((ref) {
  final vault = Vault();
  ref.onDispose(vault.dispose);
  return vault;
});

// Home/서버/mDNS 시작/알림 네비게이션은 VaultOpen 이후에만 진행함
// checking 중 Home이 잠깐 보였다 게이트로 바뀌는 깜빡임, 서버 조기 기동 방지
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
