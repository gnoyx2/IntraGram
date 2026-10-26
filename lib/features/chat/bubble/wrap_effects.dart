part of '../message_bubble.dart';

// 버블 트리는 안 건드리고 답장 스와이프 + 등장 애니메이션만 감쌈
// 소각 사라짐은 원본 내용을 안 들고 있는 _BurnGhost가 따로 맡음
extension _MessageBubbleWrapEffects on MessageBubble {
  Widget _wrapEffects(BuildContext context, Widget bubble, ColorScheme scheme) {
    // 오른쪽 스와이프로 답장: confirmDismiss에서 답장만 트리거하고 false를 반환해
    // 제자리로 복귀시킴. onReply가 없으면 원래 버블을 유지함
    // 데스크톱은 마우스 가로 드래그가 텍스트 선택이므로 제외함 (답장은 호버 버튼·메뉴 사용)
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

    // animateIn이 꺼져도 트리 모양은 그대로 둠. 등장 중 리빌드에서 꺼져도 TweenAnimationBuilder는
    // 바뀐 begin을 무시하고 진행 중인 애니메이션을 끝까지 돌림 (자식 상태도 보존됨)
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
