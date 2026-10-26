import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class AppHaptics {
  static Future<void> lightImpact() => _play(HapticFeedback.lightImpact);
  static Future<void> selectionClick() => _play(HapticFeedback.selectionClick);
  static Future<void> mediumImpact() => _play(HapticFeedback.mediumImpact);
  static Future<void> heavyImpact() => _play(HapticFeedback.heavyImpact);

  static Future<void> _play(Future<void> Function() feedback) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await feedback();
    } on MissingPluginException {
      // 진동 지원 안 하는 기기라고 동작이 끊기면 안 됨
    } on PlatformException {
      // 엔진이 포커스를 잃는 중이면 OS가 거절하기도 함
    }
  }
}
