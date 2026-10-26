part of '../app_providers.dart';

// 패닉 시 플러그인 임시 사본을 지우는 함수를 공급함. 위젯 테스트는 플랫폼 채널 없이 돌도록 교체함
final tempSweepProvider = Provider<Future<void> Function()>(
  (ref) => sweepAppTemp,
);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  unawaited(service.init());
  ref.onDispose(service.dispose);
  return service;
});

final screenshotDetectorProvider = Provider<ScreenshotDetector>((ref) {
  final detector = ScreenshotDetector();
  ref.onDispose(detector.dispose);
  return detector;
});

final foregroundServiceProvider = Provider<ForegroundService>(
  (ref) => ForegroundService(),
);

// 열려 있는 대화에만 로컬 시스템 줄을 남기고 피어에 통지함. 열린 대화가 없으면 무시함
final screenshotBridgeProvider = Provider<void>((ref) {
  final detector = ref.watch(screenshotDetectorProvider);
  final sub = detector.onScreenshot.listen((_) {
    final id = foregroundConversationId;
    if (id == null) return;
    ref
        .read(inMemoryStoreProvider)
        .addSystemMessage(
          id,
          const SystemEvent(SystemEventKind.screenshotByMe),
        );
    ref.read(linkRegistryProvider).notifyScreenshot(id);
  });
  ref.onDispose(sub.cancel);
});

// 플랫폼 채널 없는 단위 테스트에서 no-op으로 override할 수 있게 주입식으로 둠
final foregroundMessageHapticProvider = Provider<Future<void> Function()>(
  (ref) => AppHaptics.lightImpact,
);

// 소켓이 살아 있는 동안만 동작함. 앱 완전 종료 상태는 못 커버함 (푸시 서버 없음)
final notificationBridgeProvider = Provider<void>((ref) {
  final store = ref.watch(inMemoryStoreProvider);
  final service = ref.watch(notificationServiceProvider);
  final haptic = ref.watch(foregroundMessageHapticProvider);
  final sub = store.inboundActivity.listen((event) {
    if (store.appInForeground) {
      // 포그라운드에선 OS 알림 대신 짧은 햅틱만 울림. 알림 권한은 이때 처음 물음 (첫 실행 화면에서 안 물음)
      unawaited(haptic());
      unawaited(service.requestPermissionOnce());
      return;
    }
    final conversation = store.conversation(event.conversationId);
    if (conversation == null) return;
    // 알림엔 발신자 alias, 본문, 종류 전부 안 실음. 잠금 화면/알림창은 앱 밖이라
    // 다른 앱이 읽을 수 있음
    final s = S(ref.read(localeControllerProvider));
    unawaited(
      service.show(
        title: kAppName,
        body: s.t('notifications.newMessage'),
        conversationId: event.conversationId,
        channelName: s.t('notifications.channel'),
        channelDescription: s.t('notifications.channelDesc'),
      ),
    );
  });
  ref.onDispose(sub.cancel);
});
