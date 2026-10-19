part of '../transfer_tile.dart';

class _OfferActions extends StatelessWidget {
  const _OfferActions({
    required this.offeredSiblings,
    required this.onAccept,
    required this.onDecline,
    required this.onAcceptAll,
    required this.onDeclineAll,
  });

  final int offeredSiblings;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onAcceptAll;
  final VoidCallback onDeclineAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PressScale(
              child: FilledButton.tonal(
                onPressed: onAccept,
                child: Text(S.of(context).t('transfer.accept')),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onDecline,
              child: Text(S.of(context).t('transfer.decline')),
            ),
          ],
        ),
        // offered인 형제가 2개 이상일 때만 "전부" 행을 보임 (단일 파일 배치는 개별 버튼으로 충분)
        if (offeredSiblings >= 2) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: onAcceptAll,
                child: Text(
                  S.of(context).t('transfer.acceptAll', {
                    'n': '$offeredSiblings',
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: onDeclineAll,
                child: Text(S.of(context).t('transfer.declineAll')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.muted, required this.onPressed});
  final Color muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: muted,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      onPressed: onPressed,
      child: Text(S.of(context).t('transfer.cancel')),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.muted, required this.onPressed});
  final Color muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: muted,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      onPressed: onPressed,
      child: Text(S.of(context).t('transfer.retry')),
    );
  }
}
