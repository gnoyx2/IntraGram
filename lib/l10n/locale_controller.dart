import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'strings.dart';

// VaultSettings.langOverride에서 시드. null이면 OS 로케일을 따름
final localeControllerProvider = NotifierProvider<LocaleController, AppLang>(
  LocaleController.new,
);

class LocaleController extends Notifier<AppLang> {
  @override
  AppLang build() {
    final override = ref.watch(
      vaultSettingsProvider.select((s) => s.langOverride),
    );
    return resolve(override);
  }

  static AppLang resolve(String? override) {
    if (override == 'ko') return AppLang.ko;
    if (override == 'en') return AppLang.en;
    final system = PlatformDispatcher.instance.locale.languageCode;
    return system == 'ko' ? AppLang.ko : AppLang.en;
  }

  // vault가 켜져 있으면 파일에도 반영하고, 아니면 이번 세션 RAM에만 둠
  Future<void> setOverride(String? code) =>
      ref.read(vaultSettingsProvider.notifier).setLangOverride(code);
}
