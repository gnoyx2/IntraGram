part of '../message_list.dart';

// 크기/정렬만 들고 있어서 원본 텍스트/음성/전송 소스가 애니메이션 도중에도 위젯 트리에 안 남음
// reduced-motion이면 motionDuration이 0을 줘서 즉시 사라짐
class _BurnGhost extends StatelessWidget {
  const _BurnGhost({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 1, end: 0),
          duration: motionDuration(context, const Duration(milliseconds: 320)),
          curve: Curves.easeIn,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.scale(scale: 0.94 + 0.06 * value, child: child),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints.tight(size),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
