import 'dart:async';

import 'package:flutter/gestures.dart' show kPressTimeout, kTouchSlop;
import 'package:flutter/material.dart';

import 'package:intragram/theme/motion.dart';

// 누르는 동안 0.97로 살짝 들어갔다가 놓으면 돌아옴
// 포인터 이벤트만 엿봐서 자식 버튼의 탭·드래그 제스처를 가로채지 않음
// 스크롤 시작 터치에 움찔하지 않게 kPressTimeout 동안 안 움직였을 때만 눌림을 보여줌
// 햅틱은 실제 동작이 일어나는 쪽(onPressed)이 울림
class PressScale extends StatefulWidget {
  const PressScale({required this.child, this.enabled = true, super.key});

  final Widget child;

  // 비활성 버튼은 눌려도 반응하지 않아야 해서 끌 수 있게 둠
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  Timer? _timer;
  Offset? _origin;
  bool _pressed = false;

  void _set(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    _timer?.cancel();
    _origin = event.position;
    _timer = Timer(kPressTimeout, () => _set(true));
  }

  void _move(PointerMoveEvent event) {
    final origin = _origin;
    if (origin != null && (event.position - origin).distance > kTouchSlop) {
      _release();
    }
  }

  // 대기 시간 안에 뗀 짧은 탭도 눌림이 한 박자 보이게 함
  // 누르는 사이 비활성이 돼도 눌린 채 남지 않게 해제는 늘 함
  void _up(PointerUpEvent event) {
    final quickTap = widget.enabled && (_timer?.isActive ?? false);
    _release();
    if (!quickTap) return;
    _set(true);
    _timer = Timer(AppMotion.press, () => _set(false));
  }

  void _release() {
    _timer?.cancel();
    _origin = null;
    _set(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _pressed && !still ? AppMotion.pressedScale : 1,
        duration: motionDuration(context, AppMotion.press),
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}
