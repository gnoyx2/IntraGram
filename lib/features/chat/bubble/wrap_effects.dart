part of '../message_bubble.dart';

// 버블 트리는 안 건드리고 답장 스와이프 + 등장 애니메이션만 감쌈
// 소각 사라짐은 원본 내용을 안 들고 있는 _BurnGhost가 따로 담당
extension _MessageBubbleWrapEffects on MessageBubble {
  Widget _wrapEffects(BuildContext context, Widget bubble, ColorScheme scheme) {
    // 오른쪽 스와이프로 답장: confirmDismiss에서 답장만 트리거하고 항상 false를 돌려
    // 제자리로 스프링백시키는 흔한 트릭. onReply가 없으면 원래 버블
    // 데스크톱은 마우스로 가로로 끌면 글 선택이라 안 붙임 (답장은 호버 버튼·메뉴)
    final onReplyCallback = _desktop ? null : onReply;
    final swipeable = onReplyCallback == null
        ? bubble
        : Dismissible(
            key: ValueKey('reply-${message.id}'),
            direction: DismissDirection.startToEnd,
            movementDuration: motionDuration(context, AppMotion.settle),
            confirmDismiss: (_) async {
              AppHaptics.selectionClick();
              onReplyCallback(message.id);
              return false;
            },
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Icon(Icons.reply, color: scheme.primary),
            ),
            child: bubble,
          );

    // 새 스프링 시뮬레이션 대신 내장 커브 하나로 튕김
    // reduce-motion이면 duration 0 (오버슈트 없이 바로 표시)
    // animateIn이 꺼져도 트리 모양은 그대로 둠. 등장 중 리빌드에서 꺼져도 TweenAnimationBuilder는
    // 바뀐 begin을 무시하고 진행 중인 애니메이션을 끝까지 돌림 (자식 상태도 안 날아감)
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animateIn ? 0 : 1, end: 1),
      duration: motionDuration(context, const Duration(milliseconds: 320)),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: swipeable,
    );
  }
}
