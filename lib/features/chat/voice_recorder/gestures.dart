part of '../voice_recorder.dart';

extension _VoiceRecorderGestures on _VoiceRecorderButtonState {
  // onLongPress* 대신 원시 Listener로 직접 구현: Flutter는 마우스/트랙패드의 long-press slop을
  // 1px로 잡아서(터치는 18px) 맥에서 arena가 거의 항상 드래그로 밀어 시작조차 안 됨
  // 직접 타이머와 이동 허용치(_moveSlopBeforeStart)를 정해서 플랫폼 무관하게 동작함
  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    if (_tapLocked && _capture != null) {
      // 탭-고정 녹음 중엔 이 탭이 X(취소) 전용이라 새 홀드 판정을 안 걺
      return;
    }
    if (_activePointer != null) return;
    // 마우스 우클릭 등 프라이머리가 아닌 버튼은 판정 시작 안 함
    // (터치/스타일러스는 buttons가 프라이머리로 합성돼 영향 없음)
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryButton) {
      return;
    }
    _activePointer = event.pointer;
    _downPosition = event.localPosition;
    _pressTimer?.cancel();
    _pressTimer = Timer(_VoiceRecorderButtonState._holdDelay, () {
      _pressTimer = null;
      if (_downPosition != null) unawaited(_start(tapLocked: false));
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final origin = _downPosition;
    if (origin == null || _tapLocked) return;
    final delta = event.localPosition - origin;
    if (_capture == null) {
      // 시작 전(홀드 판정 대기 중)에 너무 움직이면 스크롤/드래그 시도로 보고 홀드 후보에서 뺌
      if (delta.distance > _VoiceRecorderButtonState._moveSlopBeforeStart) {
        _pressTimer?.cancel();
        _pressTimer = null;
        _downPosition = null;
      }
      return;
    }
    final progress = (-delta.dy / _VoiceRecorderButtonState._cancelDistance)
        .clamp(0.0, 1.0);
    final cancel = progress >= 1.0;
    if (progress == _cancelProgress && cancel == _cancelled) return;
    if (cancel != _cancelled) {
      cancel ? AppHaptics.mediumImpact() : AppHaptics.selectionClick();
    }
    _setCancelProgress(progress, cancel);
    _banner?.markNeedsBuild();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_tapLocked && _capture != null) {
      // 탭-고정 녹음 중 아이콘(X) 재탭은 취소. 홀드 포인터 추적과 무관한 별도 탭이라
      // _activePointer 검사를 안 거침
      unawaited(_stop(send: false));
      return;
    }
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    final wasPending = _pressTimer != null;
    _pressTimer?.cancel();
    _pressTimer = null;
    final hadDown = _downPosition != null;
    _downPosition = null;
    if (_capture != null || _busy) {
      unawaited(_stop(send: true));
    } else if (wasPending && hadDown) {
      // 홀드 임계를 못 채우고 뗀 빠른 탭은 핸즈프리 탭-고정 모드로 시작함
      unawaited(_start(tapLocked: true));
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pressTimer?.cancel();
    _pressTimer = null;
    _downPosition = null;
    if (_capture != null || _busy) unawaited(_stop(send: false));
  }
}
