import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// 로컬 알림만 있음: 서버가 없어서 앱이 살아 있고 소켓이 붙어 있을 때 온 메시지만 알림. 미지원 플랫폼·테스트에선 no-op
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  Future<void>? _initFuture;

  void Function(String conversationId)? onOpenConversation;

  bool get isReady => _ready;

  // 한 번만 초기화하고 같은 Future를 돌려씀
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    // Windows는 디스크 알림 기록 대신 네이티브 작업 표시줄 점멸만 사용함.
    const supported = <TargetPlatform>{
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    };
    if (!supported.contains(defaultTargetPlatform)) return;
    try {
      // 상태 표시줄은 알파만 써서 흰 실루엣 아이콘을 따로 둠
      const android = AndroidInitializationSettings(
        '@drawable/ic_stat_intragram',
      );
      // 권한은 init에서 안 물음 (requestPermissionOnce): 첫 화면 로컬 네트워크 팝업과 맥락 없이 겹쳤음
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      // Linux는 D-Bus 알림을 쓰며, 아이콘은 install.sh가 설치한 테마 아이콘 이름을 지정함
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

  // 첫 메시지가 왔을 때 한 번만 물음 (알림이 왜 필요한지 보이는 순간). 이미 답한 기기면 OS가 기억해서 창이 안 뜸
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

  // 꺼진 앱을 알림으로 켰으면 그 대화로 감
  Future<void> consumeLaunchPayload() async {
    await init();
    if (!_ready) return;
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch == null || !launch.didNotificationLaunchApp) return;
      final id = launch.notificationResponse?.payload;
      if (id != null && id.isNotEmpty) onOpenConversation?.call(id);
    } on Object {
      // 여기서 실패해도 앱 시작은 막으면 안 됨
    }
  }

  // channelName·channelDescription은 Android 알림 설정 화면에 보이는 앱 언어 문구임
  Future<void> show({
    required String title,
    required String body,
    required String conversationId,
    required String channelName,
    required String channelDescription,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await const MethodChannel(
          'intragram/privacy',
        ).invokeMethod<void>('requestAttention');
      } on MissingPluginException {
        // 테스트·엔진 종료 중에는 창이 없음.
      } on PlatformException {
        // 주의 요청 실패가 메시지 수신을 막지 않음.
      }
      return;
    }
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
            // 대화 여러 개 알림을 하나로 묶음
            groupKey: 'intragram_messages',
            category: AndroidNotificationCategory.message,
          ),
          // present* 플래그를 안 켜면 플러그인의 willPresent가 포그라운드 알림을 숨김. 포그라운드에선 show()를 안 부르지만
          // 백그라운드→포그라운드 전환 경합 땐 의미 있음
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
      // 채널 없음/권한 거부가 메시지 수신을 막으면 안 됨
    }
  }

  // 패닉용. 지원하면 배지도 같이 내려감
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
