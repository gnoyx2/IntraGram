part of '../chat_room_screen.dart';

// 첫 메시지 로드 중 빈 스피너 대신 실제 레이아웃(좌우 번갈아, 들쭉날쭉한 폭)을 흉내낸
// 자리표시자. 정적 이미지라 reduce-motion과 무관함
class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  static const _widths = [0.55, 0.35, 0.65, 0.42, 0.58, 0.3];

  @override
  Widget build(BuildContext context) {
    final chat = context.chat;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < _widths.length; i++)
          Align(
            alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: _widths[i],
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                height: 36,
                decoration: BoxDecoration(
                  color: (i.isEven ? chat.bubbleTheirs : chat.bubbleMine)
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
