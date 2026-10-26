import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:intragram/theme/tokens.dart';

class SearchMessagesIntent extends Intent {
  const SearchMessagesIntent();
}

// 우클릭·길게 누르기와 같은 동작 메뉴를 키보드로 여는 키 (메뉴 키, Shift+F10)
Map<ShortcutActivator, VoidCallback> menuKeyBindings(VoidCallback onMenu) => {
  const SingleActivator(LogicalKeyboardKey.contextMenu): onMenu,
  const SingleActivator(LogicalKeyboardKey.f10, shift: true): onMenu,
};

// 키보드로 옮긴 포커스를 화면 어디서나 같은 2px primary 테두리로 그림. M3 기본 포커스 표시(옅은
// 상태 레이어)는 배경 대비가 3:1이 안 나와 위치를 못 찾음 (WCAG 2.4.7, 1.4.11)
// 입력창은 자체 포커스 테두리가 있어 건너뜀. 포인터·터치로 쓸 땐 안 그림
class FocusRingLayer extends StatefulWidget {
  const FocusRingLayer({required this.child, super.key});

  final Widget child;

  @visibleForTesting
  static const Key ringKey = ValueKey<String>('focus-ring');

  @override
  State<FocusRingLayer> createState() => _FocusRingLayerState();
}

class _FocusRingLayerState extends State<FocusRingLayer> {
  final GlobalKey _layer = GlobalKey();
  Rect? _rect;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
    FocusManager.instance.addHighlightModeListener(_onModeChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    FocusManager.instance.removeHighlightModeListener(_onModeChange);
    super.dispose();
  }

  void _onFocusChange() {
    _schedule();
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _onModeChange(FocusHighlightMode _) => _onFocusChange();

  // 프레임 끝에 한 번 잼. 링이 보이는 동안엔 프레임마다 다시 재서 스크롤을 따라가고,
  // 새 프레임을 직접 요청하지 않아 화면이 가만있으면 비용이 없음
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final rect = _focusRect();
      if (rect != _rect) setState(() => _rect = rect);
      if (rect != null) _schedule();
    });
  }

  Rect? _focusRect() {
    final manager = FocusManager.instance;
    if (manager.highlightMode != FocusHighlightMode.traditional) return null;
    final node = manager.primaryFocus;
    final context = node?.context;
    if (node == null || node is FocusScopeNode || context == null) return null;
    // 말풍선 글 선택(SelectableRegion)도 마우스로 끌 때만 포커스를 받고 Tab으론 안 와서 링을 안 그림
    if (!context.mounted ||
        context.findAncestorWidgetOfExactType<EditableText>() != null ||
        context.findAncestorWidgetOfExactType<SelectableRegion>() != null) {
      return null;
    }
    final target = context.findRenderObject();
    final layer = _layer.currentContext?.findRenderObject();
    if (target is! RenderBox || layer is! RenderBox) return null;
    if (!target.attached || !target.hasSize) return null;
    final rect = MatrixUtils.transformRect(
      target.getTransformTo(layer),
      Offset.zero & target.size,
    );
    // 화면 절반 넘게 덮는 포커스는 단축키를 받으려고 화면을 감싼 컨테이너(홈 autofocus, 메시지 목록)라
    // 테두리가 아무 위치도 알려 주지 않음
    final area = layer.size.width * layer.size.height;
    if (rect.width * rect.height > area / 2) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      key: _layer,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (rect != null)
          Positioned.fromRect(
            rect: rect.inflate(2),
            child: IgnorePointer(
              child: DecoratedBox(
                key: FocusRingLayer.ringKey,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
