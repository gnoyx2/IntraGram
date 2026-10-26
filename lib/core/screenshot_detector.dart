import 'dart:async';

import 'package:flutter/services.dart';

// iOS 알림, macOS NSMetadataQuery(kMDItemIsScreenCapture), Android registerScreenCaptureCallback(API 34+)로 감지.
// iOS는 막을 순 없고 감지만 됨, Android 14 미만은 감지도 안 됨. 그 외 플랫폼은 조용함
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
