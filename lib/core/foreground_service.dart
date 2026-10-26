import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

// Android 전용. 소켓은 엔진이 쥐고 이 서비스는 OS가 프로세스를 안 죽이게 붙잡기만 함. 그래도 OS가 죽이면 못 살림 (배터리 더 씀, 옵트인)
class ForegroundService {
  ForegroundService({
    MethodChannel? channel,
    @visibleForTesting bool? isAndroid,
  }) : _channel = channel ?? const MethodChannel('intragram/foreground'),
       _isAndroid = isAndroid ?? Platform.isAndroid {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  final bool _isAndroid;

  // Android 15+ FGS 누적 시간 제한으로 서비스가 멈추면 불림: 설정은 켜졌는데 실제론 안 도는 상태를 되돌리게 함
  void Function()? onTimedOut;

  // start가 네이티브에서 실패하면(권한 거부, FGS 타입 제한 등) 불림
  void Function()? onStartFailed;

  bool _active = false;

  // 시스템이 막거나 멈춰서 설정이 꺼졌는지 (설정 화면이 이유를 보여 줌, 다시 켜면 지움)
  final ValueNotifier<bool> stoppedBySystem = ValueNotifier<bool>(false);

  // 네이티브가 성공이라고 답했을 때만 true
  bool get isActive => _active;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'onTimeout') {
      _active = false;
      stoppedBySystem.value = true;
      onTimedOut?.call();
    }
  }

  // 실패하면 false + onStartFailed. 호출부가 결과를 안 봐도 상태는 맞게 남음
  Future<bool> start() async {
    final ok = await _invoke('start');
    _active = ok;
    if (!ok) {
      stoppedBySystem.value = true;
      onStartFailed?.call();
    }
    return ok;
  }

  Future<bool> stop() async {
    final ok = await _invoke('stop');
    _active = false;
    return ok;
  }

  // stayConnected가 꺼져 있으면 (혹시 켜져 있던) 서비스를 정리만 함
  void handleLifecycle(AppLifecycleState state, {required bool stayConnected}) {
    if (!stayConnected) {
      if (state == AppLifecycleState.resumed) unawaited(stop());
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(start());
      case AppLifecycleState.resumed:
        unawaited(stop());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  // 채널 없는 환경(테스트)은 성공으로 침. 네이티브가 던진 PlatformException만 실패
  Future<bool> _invoke(String method) async {
    if (!_isAndroid) return true;
    try {
      await _channel.invokeMethod<void>(method);
      return true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }
}
