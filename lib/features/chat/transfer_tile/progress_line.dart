part of '../transfer_tile.dart';

// 넓으면 한 줄, 좁거나 글씨가 크면 다음 줄로 넘겨 남은 크기와 시간을 안 가림
class _TransferProgress extends StatelessWidget {
  const _TransferProgress({required this.transfer, required this.muted});

  final FileTransfer transfer;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final progress = transfer.progress.clamp(0.0, 1.0).toDouble();
    final rate = transfer.bytesPerSecond;
    final percent = '${(progress * 100).toStringAsFixed(0)}%';
    final remaining = formatBytes(
      math.max(0, transfer.totalBytes - transfer.transferredBytes),
    );
    final eta = _formatEta(
      s,
      transfer.totalBytes,
      transfer.transferredBytes,
      rate,
    );
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressBar(value: transfer.progress == 0 ? null : progress),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          children: [
            Text(
              rate > 0 ? '$percent · ${_formatRate(rate)}' : percent,
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              eta.isEmpty
                  ? s.t('transfer.bytesLeft', {'size': remaining})
                  : '$remaining · $eta',
              style: style,
            ),
          ],
        ),
      ],
    );
  }
}

// 6dp 캡슐 막대. 값이 바뀌면 현재 위치에서 새 목표로 부드럽게 이어감 (처음부터 다시 안 그림)
// 아직 바이트가 안 왔으면(null) 흐르는 막대
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double? value;

  static const double _height = 6;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final track = accent.withValues(alpha: 0.16);
    final target = value;
    if (target == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: LinearProgressIndicator(
          minHeight: _height,
          color: accent,
          backgroundColor: track,
        ),
      );
    }
    return Container(
      height: _height,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: target),
        duration: motionDuration(context, const Duration(milliseconds: 300)),
        curve: AppMotion.curve,
        builder: (context, fraction, _) => FractionallySizedBox(
          widthFactor: fraction,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              gradient: LinearGradient(
                colors: [accent.withValues(alpha: 0.7), accent],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
