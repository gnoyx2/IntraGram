import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

// Android 전용. 소켓은 엔진이 쥐고 있고, 이 서비스는 OS가 프로세스를 안 죽이게 붙잡기만 함
// 한계: OS가 메모리 압박 등으로 죽이면 못 살림. 배터리도 더 씀 (설정에서 옵트인, 기본 꺼짐)
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

  // Android 15+ FGS 누적 실행 시간 제한(시간 제한 있는 타입)으로 서비스가 멈추면 알림
  // 설정이 켜진 채로 실제론 안 도는 상태를 호출부가 되돌릴 수 있게 함
  void Function()? onTimedOut;

  // start가 native에서 PlatformException(권한 거부,
  // FGS 타입 제한 등)으로 실패하면 알림 onTimedOut과 같은 이유
  void Function()? onStartFailed;

  bool _active = false;

  // 시스템이 서비스를 막거나 멈춰서 설정이 저절로 꺼졌는지: 설정 화면이 이유를 보여 줌 (다시 켜면 지움)
  final ValueNotifier<bool> stoppedBySystem = ValueNotifier<bool>(false);

  // native의 성공 응답을 실제로 받았을 때만 true (낙관적으로 두지 않음)
  bool get isActive => _active;

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'onTimeout') {
      _active = false;
      stoppedBySystem.value = true;
      onTimedOut?.call();
    }
  }

  // 실패하면 false를 돌려주고 onStartFailed도 호출함
  // 호출부가 결과를 무시(unawaited)해도 상태는 정직하게 반영됨
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

  // MissingPluginException(native 등록 없는 플랫폼/테스트)은 성공 취급
  // 진짜 native가 던진 PlatformException만 false로 알림
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
