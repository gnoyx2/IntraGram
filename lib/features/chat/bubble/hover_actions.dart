part of '../message_bubble.dart';

// 마우스를 말풍선에 올리면 옆 빈 칸에 답장·반응·더보기 버튼을 띄움: 우클릭을 몰라도 동작을 찾게 함
// 데스크톱 OS에서만 그림. 터치 기기는 호버가 없고, 버튼 자리를 늘 비워 두면 폰 말풍선이 좁아짐
// 키보드·스크린 리더는 말풍선의 Enter 메뉴와 사용자 지정 동작을 쓰니 이 버튼들은 포커스·낭독에서 뺌
bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.windows => true,
  TargetPlatform.linux => true,
  _ => false,
};

extension _MessageBubbleHover on MessageBubble {
  Widget _withHoverActions(BuildContext context, WidgetRef ref, Widget bubble) {
    if (!_desktop) return bubble;
    final s = S.of(context);
    Widget button(
      IconData icon,
      String tooltip,
      void Function(BuildContext button) onPressed,
    ) => Builder(
      builder: (buttonContext) => IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: () => onPressed(buttonContext),
      ),
    );
    return _HoverActions(
      mine: message.isMine,
      buttons: [
        if (onReply != null)
          button(Icons.reply, s.t('msg.reply'), (_) => onReply!(message.id)),
        button(
          Icons.add_reaction_outlined,
          s.t('a11y.addReaction'),
          (_) => unawaited(_runAction(context, ref, 'react:more')),
        ),
        button(
          Icons.more_horiz,
          s.t('chat.more'),
          (b) => unawaited(_promptActions(context, ref, menuAnchor(b))),
        ),
      ],
      child: bubble,
    );
  }
}

class _HoverActions extends StatefulWidget {
  const _HoverActions({
    required this.mine,
    required this.buttons,
    required this.child,
  });

  final bool mine;
  final List<Widget> buttons;
  final Widget child;

  @override
  State<_HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<_HoverActions> {
  bool _hover = false;

  void _setHover(bool hover) {
    if (hover != _hover) setState(() => _hover = hover);
  }

  @override
  Widget build(BuildContext context) {
    // 자리는 늘 차지하고 보이기만 바꿈: 올릴 때마다 말풍선 폭이 바뀌어 글이 다시 흐르지 않게 함
    final bar = ExcludeFocus(
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: !_hover,
          child: AnimatedOpacity(
            opacity: _hover ? 1 : 0,
            duration: motionDuration(
              context,
              const Duration(milliseconds: 120),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.buttons,
            ),
          ),
        ),
      ),
    );
    final row = <Widget>[Flexible(child: widget.child), bar];
    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.mine ? row.reversed.toList() : row,
      ),
    );
  }
}
