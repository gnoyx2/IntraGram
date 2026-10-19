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
      // Optional feedback must not interrupt the action on unsupported devices.
    } on PlatformException {
      // The OS may decline feedback while the engine is losing focus.
    }
  }
}
