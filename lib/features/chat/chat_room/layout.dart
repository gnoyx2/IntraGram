part of '../chat_room_screen.dart';

// 배치만 바꾸고 두 자식은 같은 자리에 유지: 접힘·키보드 변화로 초안/녹음/스크롤을 버리지 않음.
class _ChatLayout extends StatelessWidget {
  const _ChatLayout({required this.messages, required this.input});

  final Widget messages;
  final Widget input;

  @override
  Widget build(BuildContext context) {
    final fold = tabletopFold(context);
    final minimumInputHeight =
        kMinInteractiveDimension +
        AppSpacing.sm * 2 +
        MediaQuery.paddingOf(context).bottom;
    // 접힘선을 본문 기준으로 옮김. 본문 안 MediaQuery는 위 여백(상태 표시줄)이 지워져 있어서 Scaffold가 잰
    // 앱바 높이(상태 표시줄 포함)를 씀. 그 높이가 바뀌면 본문 크기도 바뀌어 LayoutBuilder가 다시 읽음
    return LayoutBuilder(
      builder: (context, _) => ClipRect(
        child: CustomMultiChildLayout(
          delegate: _ChatBodyLayout(
            crease: fold?.bounds.shift(
              Offset(0, -(Scaffold.maybeOf(context)?.appBarMaxHeight ?? 0)),
            ),
            minimumInputHeight: minimumInputHeight,
          ),
          children: [
            LayoutId(
              id: 'messages',
              child: ClipRect(child: messages),
            ),
            LayoutId(
              id: 'input',
              child: SingleChildScrollView(reverse: true, child: input),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBodyLayout extends MultiChildLayoutDelegate {
  _ChatBodyLayout({required this.crease, required this.minimumInputHeight});

  final Rect? crease;
  final double minimumInputHeight;

  @override
  void performLayout(Size size) {
    final top = (crease?.top ?? size.height).clamp(0.0, size.height);
    final bottom = (crease?.bottom ?? size.height).clamp(0.0, size.height);
    // 키보드가 아래 화면을 가리면 입력창도 위쪽으로 옮겨 접힘선 바로 위에 붙임.
    final useLower =
        crease != null && size.height - bottom >= minimumInputHeight;
    final end = crease == null || useLower ? size.height : top;
    final input = layoutChild(
      'input',
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: useLower ? size.height - bottom : end,
      ),
    );
    positionChild('input', Offset(0, end - input.height));
    layoutChild(
      'messages',
      BoxConstraints.tight(
        Size(size.width, useLower ? top : end - input.height),
      ),
    );
    positionChild('messages', Offset.zero);
  }

  @override
  bool shouldRelayout(_ChatBodyLayout oldDelegate) =>
      crease != oldDelegate.crease ||
      minimumInputHeight != oldDelegate.minimumInputHeight;
}
