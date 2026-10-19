import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// 서버가 없어서 앱이 완전히 종료된 상태의 푸시는 불가능. 앱이 살아 있고 소켓이
// 붙어 있는 동안 온 인바운드 메시지에만 동작함. 미지원 플랫폼(리눅스 CI, 테스트)에선 no-op
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  Future<void>? _initFuture;

  void Function(String conversationId)? onOpenConversation;

  bool get isReady => _ready;

  // 한 번만 초기화하고 같은 Future를 재사용 (consumeLaunchPayload가 init 완료를 기다릴 수 있게)
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    // Windows는 이 플러그인 버전(18.x)에 구현이 없어 OS 알림을 안 띄움 (README에 적음)
    const supported = <TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    };
    if (!supported.contains(defaultTargetPlatform)) return;
    try {
      // 상태 표시줄은 알파만 써서 흰색으로 칠함: 컬러 런처 아이콘 대신 흰 실루엣
      const android = AndroidInitializationSettings(
        '@drawable/ic_stat_intragram',
      );
      // 권한은 init에서 묻지 않음 (requestPermissionOnce): 첫 화면에서 로컬 네트워크 팝업과 맥락 없이 겹쳤음
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      // Linux는 D-Bus 알림. 아이콘은 install.sh가 깐 아이콘 테마 이름
      final linux = LinuxInitializationSettings(
        defaultActionName: 'Open',
        defaultIcon: ThemeLinuxIcon('intragram'),
      );
      await _plugin.initialize(
        InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
          linux: linux,
        ),
        onDidReceiveNotificationResponse: (response) {
          final id = response.payload;
          if (id != null && id.isNotEmpty) onOpenConversation?.call(id);
        },
      );
      _ready = true;
    } on Object {
      _ready = false;
    }
  }

  bool _askedThisRun = false;

  // 첫 메시지가 왔을 때(앱이 앞에 있을 때) 한 번만 물음: 알림이 왜 필요한지 보이는 순간. OS가 답을
  // 기억해서 이미 답한 기기에선 창이 다시 안 뜸 (Android 13+ POST_NOTIFICATIONS, iOS·macOS 알림)
  Future<void> requestPermissionOnce() async {
    if (_askedThisRun) return;
    _askedThisRun = true;
    await init();
    if (!_ready) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
        case TargetPlatform.iOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
        case TargetPlatform.macOS:
          await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
        default:
          break;
      }
    } on Object {
      // 권한 창을 못 띄워도 대화는 계속됨 (알림만 안 뜸)
    }
  }

  // 콜드 스타트 라우팅: 앱이 꺼진 상태에서 탭한 알림의 payload(대화 id)로 onOpenConversation 호출
  Future<void> consumeLaunchPayload() async {
    await init();
    if (!_ready) return;
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch == null || !launch.didNotificationLaunchApp) return;
      final id = launch.notificationResponse?.payload;
      if (id != null && id.isNotEmpty) onOpenConversation?.call(id);
    } on Object {
      // 콜드 스타트 라우팅 실패가 앱 시작을 막으면 안 됨
    }
  }

  // channelName·channelDescription은 Android 알림 설정 화면에 보이는 앱 언어 문구
  Future<void> show({
    required String title,
    required String body,
    required String conversationId,
    required String channelName,
    required String channelDescription,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        conversationId.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            // N개 대화의 메시지를 알림창에서 하나로 묶음
            groupKey: 'intragram_messages',
            category: AndroidNotificationCategory.message,
          ),
          // present* 플래그를 안 켜면 flutter_local_notifications의 willPresent 델리게이트가
          // 포그라운드 알림을 조용히 숨김. 포그라운드에선 show()를 안 부르지만
          // 백그라운드->포그라운드 전환 경합 같은 좁은 창에선 의미가 있음
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
        ),
        payload: conversationId,
      );
    } on Object {
      // 채널 없음/권한 거부가 채팅을 죽이면 안 됨
    }
  }

  // 패닉 와이프용. 플랫폼이 지원하면 배지 카운트도 같이 내려감
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } on Object {
      // 알림 정리 실패가 패닉 경로를 막으면 안 됨
    }
  }

  void dispose() {}
}
