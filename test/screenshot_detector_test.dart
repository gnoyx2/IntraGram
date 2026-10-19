import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/screenshot_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('intragram/screenshot');

  Future<void> fireFromPlatform(String method) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) {},
        );
  }

  test('emits an event when the platform reports a screenshot', () async {
    final detector = ScreenshotDetector(channel: channel);
    addTearDown(detector.dispose);

    final events = <void>[];
    final sub = detector.onScreenshot.listen(events.add);
    addTearDown(sub.cancel);

    await fireFromPlatform('onScreenshot');
    await pumpEventQueue();

    expect(events, hasLength(1));
  });

  test('ignores unrelated platform calls', () async {
    final detector = ScreenshotDetector(channel: channel);
    addTearDown(detector.dispose);

    final events = <void>[];
    final sub = detector.onScreenshot.listen(events.add);
    addTearDown(sub.cancel);

    await fireFromPlatform('somethingElse');
    await pumpEventQueue();

    expect(events, isEmpty);
  });

  test('dispose unhooks the channel handler', () async {
    ScreenshotDetector(channel: channel).dispose();
    // 핸들러가 풀렸으면 이 호출은 아무 데도 안 감 (예외 없이 통과)
    await fireFromPlatform('onScreenshot');
  });
}
