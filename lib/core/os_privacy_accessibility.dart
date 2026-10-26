part of 'os_privacy.dart';

abstract final class _PrivacyAccessibility {
  static final reduceTransparency = ValueNotifier<bool>(false);
  static final reduceMotion = ValueNotifier<bool>(false);
  static final highContrast = ValueNotifier<bool>(false);
  static final _settings = {
    'reduceTransparency': reduceTransparency,
    'reduceMotion': reduceMotion,
    'highContrast': highContrast,
  };
  static final _revisions = <String, int>{};
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    OsPrivacy._channel.setMethodCallHandler((call) async {
      final key = switch (call.method) {
        'onReduceTransparencyChanged' => 'reduceTransparency',
        'onReduceMotionChanged' => 'reduceMotion',
        'onHighContrastChanged' => 'highContrast',
        _ => null,
      };
      if (key != null && call.arguments is bool) {
        _revisions[key] = (_revisions[key] ?? 0) + 1;
        _settings[key]!.value = call.arguments as bool;
      } else if (call.method == 'onDisplayRegions') {
        DisplayRegions.update(call.arguments);
      }
    });
    _listening = true;
  }

  static Future<void> refreshAll() async {
    await Future.wait(_settings.keys.map(refresh));
  }

  static Future<void> refresh(String key) async {
    _listen();
    final revision = _revisions[key];
    try {
      final value = await OsPrivacy._channel.invokeMethod<bool>(key);
      // 조회 중 도착한 새 설정을 오래된 조회 응답으로 덮지 않음.
      if (value != null && revision == _revisions[key]) {
        _settings[key]!.value = value;
      }
    } on MissingPluginException {
      // 채널이 없는 플랫폼은 Flutter의 MediaQuery를 따름.
    } on PlatformException {
      // 조회 실패가 마지막 접근성 상태를 덮지 않게 함.
    }
  }

  static Future<void> refreshDisplayRegions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _listen();
    try {
      DisplayRegions.update(
        await OsPrivacy._channel.invokeMethod<Object>('displayRegions'),
      );
    } on MissingPluginException {
      // OS가 접힘선을 안 알려 주면 화면 크기로 짐작함.
    } on PlatformException {
      // 조회 실패 시 기존 값을 유지하며 초기 상태(null)면 화면 크기로 짐작함.
    }
  }
}
