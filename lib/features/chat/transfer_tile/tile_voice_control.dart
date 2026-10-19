part of '../transfer_tile.dart';

extension _TransferTileVoiceControl on TransferTile {
  Widget _voiceControl(
    BuildContext context,
    FileTransfer transfer,
    Color muted,
    LinkRegistry registry,
  ) {
    final s = S.of(context);
    final lineStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: muted);
    // 보낸 쪽은 녹음 직후부터 자기 바이트를 들고 있어서 상대가 수락 전이거나 전송 중이어도
    // 바로 재생 가능해야 함. 그래서 state 스위치보다 먼저 체크함
    // 단 실패/무름 상태는 재생 가능 여부와 별개로 같이 보여줌 (바이트가 있다고 업로드 실패를 가리면 안 됨)
    final bytes = transfer.voiceBytes;
    final player = bytes == null
        ? null
        : _VoicePlayer(
            bytes: bytes,
            color: onBubble,
            encrypted: transfer.encrypted,
          );
    if (player != null && transfer.state != TransferState.failed) {
      return player;
    }
    switch (transfer.state) {
      case TransferState.complete:
        return Text(
          mine ? s.t('transfer.voiceSent') : s.t('transfer.voiceGone'),
          style: lineStyle,
        );
      case TransferState.failed:
        final status = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(s.t('transfer.voiceFailed'), style: lineStyle),
            ),
            const SizedBox(width: AppSpacing.xs),
            _RetryButton(
              muted: muted,
              onPressed: () => registry.retryTransfer(transfer.id),
            ),
          ],
        );
        if (player == null) return status;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            player,
            const SizedBox(height: AppSpacing.xxs),
            status,
          ],
        );
      case TransferState.rejected:
      case TransferState.cancelled:
        return Text(s.t('transfer.voiceCancelled'), style: lineStyle);
      case TransferState.offered:
        // 자동 수락이 꺼져 있으면 음성도 일반 파일처럼 수락/거절을 물음
        if (transfer.direction == TransferDirection.incoming) {
          return _OfferActions(
            offeredSiblings: 0,
            onAccept: () {
              AppHaptics.lightImpact();
              registry.acceptTransfer(transfer.id);
            },
            onDecline: () => registry.rejectTransfer(transfer.id),
            onAcceptAll: () {},
            onDeclineAll: () {},
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: muted),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(s.t('transfer.waitingForPeer'), style: lineStyle),
          ],
        );
      case TransferState.accepted:
      case TransferState.transferring:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: muted),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              mine
                  ? s.t('transfer.waitingForPeer')
                  : s.t('transfer.voiceReceiving'),
              style: lineStyle,
            ),
          ],
        );
    }
  }
}
