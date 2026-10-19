import 'package:flutter/material.dart';

import 'package:intragram/theme/tokens.dart';

// 길게 누르기(터치)는 바텀 시트, 마우스 우클릭·메뉴 키는 그 자리 팝업 메뉴 (데스크톱 관례)
// builder 안에서 Navigator.of(context).pop(값)으로 고른 값을 돌려줌. 시트·메뉴 둘 다 같은 길
Future<T?> showActionMenu<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Offset? at,
}) {
  if (at == null) {
    return showModalBottomSheet<T>(
      context: context,
      // 늘어난 ListTile 패딩 + 드래그 핸들 때문에 낮은 화면에서 넘칠 수 있어 스크롤 가능하게
      builder: (sheetContext) =>
          SafeArea(child: SingleChildScrollView(child: builder(sheetContext))),
    );
  }
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final point = overlay.globalToLocal(at);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      point & Size.zero,
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
    items: [_MenuBody<T>(builder)],
  );
}

// 키보드(메뉴 키·Shift+F10·Enter)로 열 때 메뉴를 띄울 자리: 그 위젯 왼쪽 위 안쪽
Offset menuAnchor(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(const Offset(AppSpacing.lg, AppSpacing.lg));
}

// 시트에 넣던 내용을 메뉴 안에 그대로 그리는 칸
class _MenuBody<T> extends PopupMenuEntry<T> {
  const _MenuBody(this.builder);

  final WidgetBuilder builder;

  // 메뉴 첫 위치 계산용 근사치
  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(T? value) => false;

  @override
  State<_MenuBody<T>> createState() => _MenuBodyState<T>();
}

class _MenuBodyState<T> extends State<_MenuBody<T>> {
  @override
  Widget build(BuildContext context) => widget.builder(context);
}
