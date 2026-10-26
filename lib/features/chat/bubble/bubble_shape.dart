part of '../message_bubble.dart';

// 묶음 안에서는 위아래 1px씩만 띄워 한 덩어리로 보이게 함
const double _groupGap = AppSpacing.xxs / 2;

EdgeInsets _bubbleMargin(bool joinsPrevious, bool joinsNext) =>
    EdgeInsets.fromLTRB(
      AppSpacing.sm,
      joinsPrevious ? _groupGap : AppSpacing.xs,
      AppSpacing.sm,
      joinsNext ? _groupGap : AppSpacing.xs,
    );

// 발신 방향 모서리만 묶음 위치에 따라 바뀜. 위 이웃과 붙으면 위쪽을 tail로 좁히고
// 아래쪽은 늘 tail. 묶음 마지막(또는 단독) 말풍선만 아래 모서리에 꼬리가 달림
// 타이핑 표시(TypingDots)도 단독 상대 말풍선 모양으로 이걸 그대로 씀
ShapeDecoration bubbleDecoration({
  required ChatColors chat,
  required ColorScheme scheme,
  required bool mine,
  required bool joinsPrevious,
  required bool joinsNext,
}) {
  const round = Radius.circular(AppRadius.lg);
  const tight = Radius.circular(AppRadius.tail);
  final top = joinsPrevious ? tight : round;
  final radius = BorderRadius.only(
    topLeft: mine ? round : top,
    topRight: mine ? top : round,
    bottomLeft: mine ? round : tight,
    bottomRight: mine ? tight : round,
  );
  final shadowVisible = chat.bubbleShadow.a > 0;
  // 0.5dp 경계로 캔버스와 분리. 내 말풍선 윤곽은 테마 토큰이라 다크에선 투명해서 안 그림
  final edge = mine ? chat.bubbleMineEdge : scheme.outlineVariant;
  return ShapeDecoration(
    color: mine ? null : chat.bubbleTheirs,
    gradient: mine
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [chat.bubbleMineTop, chat.bubbleMine],
          )
        : null,
    shape: _BubbleBorder(
      radius: radius,
      tail: joinsNext ? null : (mine ? _Tail.right : _Tail.left),
      side: edge.a > 0
          ? BorderSide(
              color: edge,
              width: scheme.outlineVariant == scheme.outline
                  ? AppBorder.defined
                  : AppBorder.hairline,
            )
          : BorderSide.none,
    ),
    shadows: shadowVisible
        ? [
            BoxShadow(
              color: chat.bubbleShadow,
              blurRadius: mine ? 6 : 12,
              offset: const Offset(0, 2),
            ),
          ]
        : null,
  );
}

enum _Tail { left, right }

// 둥근 사각형에 iMessage식 꼬리를 합친 말풍선 외곽선. 꼬리는 말풍선 좌우 여백 안으로 삐져나옴
class _BubbleBorder extends ShapeBorder {
  const _BubbleBorder({
    required this.radius,
    this.tail,
    this.side = BorderSide.none,
  });

  final BorderRadius radius;
  final _Tail? tail;
  final BorderSide side;

  static const double _reach = 6;
  static const double _rise = 14;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Path()..addRRect(radius.toRRect(rect));
    final tail = this.tail;
    if (tail == null) return body;
    return Path.combine(PathOperation.union, body, _tailPath(rect, tail));
  }

  // 아래 모서리에서 바깥으로 휘어 나가는 꼬리. 바닥선은 말풍선 바닥과 같은 높이
  Path _tailPath(Rect rect, _Tail tail) {
    final dir = tail == _Tail.right ? 1.0 : -1.0;
    final edge = tail == _Tail.right ? rect.right : rect.left;
    return Path()
      ..moveTo(edge - dir * _rise, rect.bottom)
      ..lineTo(edge + dir * _reach, rect.bottom)
      ..quadraticBezierTo(
        edge + dir,
        rect.bottom - 3,
        edge,
        rect.bottom - _rise,
      )
      ..lineTo(edge - dir * _rise, rect.bottom - _rise)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      _BubbleBorder(radius: radius * t, tail: tail, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is _BubbleBorder &&
      other.radius == radius &&
      other.tail == tail &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, tail, side);
}
