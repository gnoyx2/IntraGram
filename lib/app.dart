import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_commands.dart';
import 'app_navigator.dart';
import 'app_providers.dart';
import 'core/constants.dart';
import 'core/display_regions.dart';
import 'core/foreground_service.dart';
import 'core/mobile_file_source.dart';
import 'core/os_privacy.dart';
import 'core/voice_producer_registry.dart';
import 'features/chat/open_chat.dart';
import 'features/home/home_actions.dart' show manualConnect;
import 'features/home/home_screen.dart';
import 'features/settings/pin_gate_screen.dart';
import 'l10n/locale_controller.dart';
import 'l10n/strings.dart';
import 'network/link_registry.dart';
import 'network/server_controller.dart';
import 'store/in_memory_store.dart';
import 'store/vault.dart';
import 'theme/app_theme.dart';
import 'widgets/keyboard_access.dart';
import 'widgets/privacy_shield.dart';

part 'app_accessibility.dart';
part 'app_lock.dart';

class IntraGramApp extends ConsumerStatefulWidget {
  const IntraGramApp({super.key});

  @override
  ConsumerState<IntraGramApp> createState() => _IntraGramAppState();
}

class _IntraGramAppState extends ConsumerState<IntraGramApp>
    with WidgetsBindingObserver, _AppAccessibility {
  late final ConversationOpener _opener;
  late final ProviderContainer _providers;
  // 자동 재잠금 (app_lock.dart)
  Timer? _lockTimer;
  DateTime? _backgroundAt;

  @override
  void initState() {
    super.initState();
    _providers = ProviderScope.containerOf(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _opener = ConversationOpener(
      push: _pushConversation,
      gateUp: () => ref.read(vaultAccessProvider) is! VaultOpen,
    );
    ref.read(notificationServiceProvider).onOpenConversation = _opener.open;
    _watchAccessibility();
    // 서버·mDNS는 여기서 안 켬: 게이트를 통과한 뒤 build의 listen이 켬 (PIN 게이트 전에 서버가 도는 틈이 없게)

    // FGS 시간 제한으로 서비스가 멈추면 "백그라운드 연결 유지" 설정도 같이 끔
    ref.read(foregroundServiceProvider).onTimedOut = () {
      unawaited(
        ref.read(vaultSettingsProvider.notifier).setStayConnected(false),
      );
    };
    // 네이티브 쪽 FGS 시작 실패(권한 거부 등)도 같은 방식으로 설정 롤백
    ref.read(foregroundServiceProvider).onStartFailed = () {
      unawaited(
        ref.read(vaultSettingsProvider.notifier).setStayConnected(false),
      );
    };
  }

  bool _gateOpenedOnce = false;

  void _onGateOpened() {
    if (_gateOpenedOnce) return;
    _gateOpenedOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final serverController = ref.read(serverControllerProvider.notifier);
      serverController.start();
      // 이미 resumed라 전이 이벤트가 안 와서 점검 타이머를 직접 켬
      serverController.setForeground(true);
      unawaited(ref.read(notificationServiceProvider).consumeLaunchPayload());
    });
    _opener.gateCleared();
  }

  // 다음 프레임에 push. 잠금 해제 직후의 트리 재빌드와 충돌 방지
  void _pushConversation(String conversationId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;
      if (navigator != null) pushChat(navigator, conversationId);
    });
  }

  @override
  void dispose() {
    _cancelAutoLock();
    _stopAccessibility();
    WidgetsBinding.instance.removeObserver(this);
    _persistIfEnabled();
    _wipe();
    super.dispose();
  }

  // 앱이 떠 있는 채로 OS 언어가 바뀜 (Android는 locale 변경을 액티비티가 직접 받아 재생성 안 됨)
  @override
  void didChangeLocales(List<Locale>? locales) =>
      ref.invalidate(localeControllerProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 자동 재연결은 일부러 안 함 (오프라인 배너에서 수동으로만): 동시 재연결 폭주 방지
    _handleAutoLock(state);
    final foreground = state == AppLifecycleState.resumed;
    ref.read(inMemoryStoreProvider).appInForeground = foreground;
    if (foreground) {
      unawaited(OsPrivacy.onAppResumed());
      unawaited(OsPrivacy.refreshAccessibility());
    }

    // 서버·mDNS는 망을 따라감: 돌아오면 바인드 주소를 보고 백그라운드면 점검을 멈춤
    if (_gateOpenedOnce) {
      ref.read(serverControllerProvider.notifier).setForeground(foreground);
    }

    ref
        .read(foregroundServiceProvider)
        .handleLifecycle(
          state,
          // 잠긴(재잠금 중 포함) 세션은 백그라운드 연결을 유지하지 않음
          stayConnected:
              ref.read(vaultAccessProvider) is VaultOpen &&
              ref.read(vaultSettingsProvider).stayConnectedInBackground,
        );

    // 디바운스 저장이 최신이어도 백그라운드 진입 시 안전망으로 한 번 더 저장
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistIfEnabled();
    }
    // detached는 OS가 엔진을 곧 없앤다는 신호. RAM 스크럽 마지막 기회
    if (state == AppLifecycleState.detached) {
      _wipe();
    }
  }

  void _persistIfEnabled() {
    final settings = _providers.read(vaultSettingsProvider);
    if (!settings.enabled ||
        !_providers.read(vaultAccessProvider.notifier).canWriteArchive) {
      return;
    }
    unawaited(
      _providers
          .read(vaultProvider)
          .save(_providers.read(inMemoryStoreProvider).toSnapshot(settings)),
    );
  }

  void _wipe() {
    // 링크부터 끊음. RAM을 먼저 비우면 그 사이 도착한 프레임이 지운 상태를 되살림
    // (executePanicWipe와 같은 순서). detached는 곧 종료라 await 안 함
    unawaited(_providers.read(linkRegistryProvider).disposeAll());
    _providers.read(inMemoryStoreProvider).secureWipe();
    OsPrivacy.clearDecodedImages();
  }

  @override
  Widget build(BuildContext context) {
    // void provider들은 watch로 살려둠 (알림 / mDNS room 힌트 / 스크린샷 브리지)
    ref.watch(notificationBridgeProvider);
    ref.watch(roomHintBridgeProvider);
    ref.watch(screenshotBridgeProvider);
    // checking이 비동기로 끝나서 initState가 아닌 여기서 게이트 전이를 잡음
    ref.listen<VaultAccessState>(vaultAccessProvider, (_, next) {
      if (next is VaultOpen) _onGateOpened();
    });

    final access = ref.watch(vaultAccessProvider);
    final Widget home = switch (access) {
      VaultChecking() => const _VaultCheckingScreen(),
      VaultLocked() => const PinGateScreen(),
      VaultOpen() => const HomeScreen(),
    };

    final lang = ref.watch(localeControllerProvider);

    return LocaleScope(
      lang: lang,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: _theme(dark: false),
        darkTheme: _theme(dark: true),
        highContrastTheme: _theme(dark: false, highContrast: true),
        highContrastDarkTheme: _theme(dark: true, highContrast: true),
        themeMode: ThemeMode.system,
        // 뒤로·메뉴 툴팁, 텍스트 선택 도구 막대, 스크린리더 라벨 같은 프레임워크 문구도 앱 언어를 따름
        locale: Locale(lang.name),
        supportedLocales: const [Locale('en'), Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
        builder: (context, child) => _withAccessibility(
          context,
          PrivacyShield(
            child: FocusRingLayer(
              child: AppCommands(
                navigatorKey: navigatorKey,
                unlocked: access is VaultOpen,
                onNewConnection: (context) =>
                    unawaited(manualConnect(context, ref)),
                onTextSize: _stepTextSize,
                child: Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    // 재잠금 중엔 밑에서 대화 경로가 닫히는 동안 내용이 안 보이게 덮음
                    if (access is VaultChecking)
                      const Positioned.fill(child: _VaultCheckingScreen()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
