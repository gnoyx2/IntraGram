part of '../transfer_tile.dart';

// 40dp 액센트 원형 재생 버튼 (탭 영역은 48dp). 누르면 살짝 들어가고
// 재생·일시정지 글리프는 작게 튀며 바뀜. 햅틱은 _VoicePlayer._toggle이 울림
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.onPressed,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onPressed;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onAccent = scheme.onPrimary;
    final Widget glyph = loading
        ? SizedBox.square(
            key: const ValueKey('loading'),
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
          )
        : Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey(playing),
            size: 24,
          );
    return PressScale(
      enabled: !loading,
      child: IconButton.filled(
        onPressed: loading ? null : onPressed,
        tooltip: S.of(context).t(playing ? 'transfer.pause' : 'transfer.play'),
        style: IconButton.styleFrom(
          // 로딩 중엔 비활성이지만 기본 회색 대신 액센트 원을 유지해 스피너가 보이게 함
          disabledBackgroundColor: scheme.primary,
          disabledForegroundColor: onAccent,
          fixedSize: const Size.square(_size),
          minimumSize: const Size.square(_size),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        icon: AnimatedSwitcher(
          duration: motionDuration(context, AppMotion.settle),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: glyph,
        ),
      ),
    );
  }
}
