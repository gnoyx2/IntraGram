import 'dart:async';

import 'package:flutter/services.dart';

// iOS 알림, macOS NSMetadataQuery(kMDItemIsScreenCapture), Android
// registerScreenCaptureCallback(API 34+)로 감지. 그 외 플랫폼은 스트림이 조용함
// 한계: iOS는 감지만 되고 차단 불가, Android 14 미만은 감지 불가
class ScreenshotDetector {
  ScreenshotDetector({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('intragram/screenshot') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<void> _events = StreamController<void>.broadcast();

  Stream<void> get onScreenshot => _events.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'onScreenshot' && !_events.isClosed) _events.add(null);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _events.close();
  }
}
