part of 'app.dart';

// 백그라운드 자동 재잠금. 콜드 스타트와 같은 상태(RAM 비움 + PIN 게이트)로 되돌리고
// 잠금 해제 때 vault에서 다시 하이드레이트함. 순서는 패닉처럼 입구부터 닫음:
// 화면/저장 막기 -> 녹음·FGS·서버·링크 정지 -> native 소스 해제 -> 최종 상태 봉인 + 키 폐기 -> RAM 소각
// 링크를 먼저 닫아야 저장 뒤 도착한 프레임이 봉인에서 빠지거나 소각 뒤 되살아나지 않음
// 단계가 실패하거나 kPanicStepTimeout을 넘겨도 잠금과 소각은 끝까지 가고, 첫 실패만 다시 던짐
Future<void> relockSession({
  required InMemoryStore store,
  required LinkRegistry registry,
  required ServerController serverController,
  required ForegroundService foregroundService,
  required VaultAccessNotifier vaultAccess,
  required VaultSettings settings,
  VoiceProducerRegistry? voiceProducers,
  Future<void> Function()? releaseNativeSources,
}) async {
  final relockGeneration = vaultAccess.beginRelock();
  Object? failure;
  StackTrace? failureStack;
  Future<void> step(Future<void> Function() run) async {
    try {
      await run().timeout(kPanicStepTimeout);
    } on Object catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
  }

  try {
    await Future.wait(<Future<void>>[
      step((voiceProducers ?? VoiceProducerRegistry.instance).stopAll),
      step(foregroundService.stop),
      step(serverController.stop),
      step(registry.disposeAll),
    ]);
    await step(releaseNativeSources ?? MobileFileSource.releaseAll);
    await step(
      () => vaultAccess.finishRelock(
        store.toSnapshot(settings),
        relockGeneration,
      ),
    );
  } finally {
    vaultAccess.completeRelock(relockGeneration);
    store.secureWipe();
    OsPrivacy.clearDecodedImages();
  }
  final error = failure;
  if (error != null) Error.throwWithStackTrace(error, failureStack!);
}

extension _AppLock on _IntraGramAppState {
  // hidden/paused에 들어간 시각부터 잼. OS가 앱을 멈춰 타이머가 못 돌았어도
  // 복귀(resumed) 때 실제 경과 시간으로 다시 판단함 (기기 잠자기 동안도 흐르는 벽시계 기준)
  void _handleAutoLock(AppLifecycleState state) {
    final settings = ref.read(vaultSettingsProvider);
    if (!settings.enabled ||
        !settings.pinProtected ||
        ref.read(vaultAccessProvider) is! VaultOpen) {
      return;
    }
    final timeout = Duration(minutes: settings.autoLockMinutes);
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgroundAt ??= DateTime.now();
      _lockTimer ??= Timer(timeout, () => unawaited(_relock()));
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundAt;
      _cancelAutoLock();
      if (since != null && DateTime.now().difference(since) >= timeout) {
        unawaited(_relock());
      }
    }
  }

  void _cancelAutoLock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _backgroundAt = null;
  }

  Future<void> _relock() async {
    if (!mounted || ref.read(vaultAccessProvider) is! VaultOpen) return;
    _cancelAutoLock();
    _gateOpenedOnce = false;
    // 대화/시트 경로는 닫음. 닫히는 애니메이션은 VaultChecking 커버(build) 밑에서 돎
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    try {
      await relockSession(
        store: ref.read(inMemoryStoreProvider),
        registry: ref.read(linkRegistryProvider),
        serverController: ref.read(serverControllerProvider.notifier),
        foregroundService: ref.read(foregroundServiceProvider),
        vaultAccess: ref.read(vaultAccessProvider.notifier),
        settings: ref.read(vaultSettingsProvider),
      );
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'IntraGram lock',
        ),
      );
    } finally {
      // disposeAll한 레지스트리는 새 링크를 안 받아서 잠금 해제 뒤 쓸 것을 새로 만듦 (패닉과 같음)
      if (mounted) ref.invalidate(linkRegistryProvider);
    }
  }
}

// 봉인 확인 중엔 Home/게이트 어느 쪽도 단정 안 함. 틀리면 Home이 한 프레임 깜빡임
class _VaultCheckingScreen extends StatelessWidget {
  const _VaultCheckingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
