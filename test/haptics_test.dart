import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <Object?>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.arguments);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final platform in TargetPlatform.values) {
    test('${platform.name}: haptics only reach mobile platforms', () async {
      debugDefaultTargetPlatformOverride = platform;
      await AppHaptics.lightImpact();
      await AppHaptics.selectionClick();
      await AppHaptics.mediumImpact();
      await AppHaptics.heavyImpact();
      expect(
        calls,
        platform == TargetPlatform.android || platform == TargetPlatform.iOS
            ? [
                'HapticFeedbackType.lightImpact',
                'HapticFeedbackType.selectionClick',
                'HapticFeedbackType.mediumImpact',
                'HapticFeedbackType.heavyImpact',
              ]
            : isEmpty,
      );
    });
  }

  for (final error in [
    MissingPluginException(),
    PlatformException(code: 'off'),
  ]) {
    test('optional feedback tolerates ${error.runtimeType}', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (_) async {
        throw error;
      });
      await expectLater(AppHaptics.lightImpact(), completes);
    });
  }
}
