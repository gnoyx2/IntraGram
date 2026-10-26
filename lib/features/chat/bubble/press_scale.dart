part of '../message_bubble.dart';

// 우클릭을 누르는 순간 이김: 글 선택 영역의 우클릭보다 말풍선 동작 메뉴가 먼저 뜸.
// allowed가 false면(선택한 글이 있음) 안 끼어서 선택 영역의 복사 메뉴가 뜸
class _MenuClick extends TapGestureRecognizer {
  _MenuClick({required this.allowed});

  final bool Function() allowed;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      allowed() && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

// 말풍선 눌림. 안쪽 링크·버튼이 탭을 이기면 말풍선은 안 눌림. 햅틱은 확정된 탭에만 (롱프레스는 _promptActions가 울림).
// 탭 인식기가 배경의 키보드 내리기 탭을 이겨서 그 동작도 여기서 함
class _PressScale extends StatefulWidget {
  const _PressScale({
    required this.onLongPress,
    required this.child,
    this.onTap,
    this.onSecondaryTapUp,
  });

  final VoidCallback onLongPress;
  final Widget child;

  // 실패한 글의 다시 보내기처럼 말풍선 탭에 동작이 붙을 때만 줌. 햅틱은 그 동작이 직접 울림
  final VoidCallback? onTap;

  // 우클릭(데스크톱)은 커서 자리에 같은 동작 메뉴를 엶 (롱프레스는 마우스로 닿을 수 없는 제스처)
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;
  Timer? _tapRelease;

  void _setPressed(bool value) {
    _tapRelease?.cancel();
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  void dispose() {
    _tapRelease?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        final onTap = widget.onTap;
        if (onTap == null) {
          AppHaptics.lightImpact();
        } else {
          onTap();
        }
        FocusScope.of(context).unfocus();
        if (still) return;
        // 같은 프레임에 눌렀다 떼는 짧은 탭도 한 박자 보이게 함
        _setPressed(true);
        _tapRelease = Timer(AppMotion.press, () => _setPressed(false));
      },
      onLongPressStart: (_) => _setPressed(true),
      onLongPressEnd: (_) => _setPressed(false),
      onLongPressCancel: () => _setPressed(false),
      onLongPress: widget.onLongPress,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      child: AnimatedScale(
        scale: _pressed && !still ? AppMotion.pressedScale : 1,
        duration: motionDuration(context, AppMotion.press),
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}
