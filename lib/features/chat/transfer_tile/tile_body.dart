part of '../transfer_tile.dart';

extension _TransferTileBody on TransferTile {
  Widget _control(
    BuildContext context,
    WidgetRef ref,
    FileTransfer transfer,
    Color muted,
  ) {
    final registry = ref.read(linkRegistryProvider);
    if (transfer.voice) {
      return _voiceControl(context, transfer, muted, registry);
    }
    switch (transfer.state) {
      case TransferState.offered:
        if (transfer.direction == TransferDirection.incoming) {
          final batchId = transfer.batchId;
          final offeredSiblings = batchId == null
              ? 0
              : ref
                    .watch(
                      transfersInBatchProvider((
                        conversationId: transfer.conversationId,
                        batchId: batchId,
                      )),
                    )
                    .where(
                      (t) =>
                          t.direction == TransferDirection.incoming &&
                          t.state == TransferState.offered,
                    )
                    .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _OfferedFilePreview(
                thumbBytes: transfer.thumbBytes,
                preview: transfer.preview,
                mutedTextColor: muted,
              ),
              _OfferActions(
                offeredSiblings: offeredSiblings,
                onAccept: () {
                  AppHaptics.lightImpact();
                  acceptWithPicker(
                    context,
                    () => registry.acceptTransfer(transfer.id),
                  );
                },
                onDecline: () => registry.rejectTransfer(transfer.id),
                onAcceptAll: () => acceptWithPicker(
                  context,
                  () => registry.acceptBatch(transfer.conversationId, batchId!),
                ),
                onDeclineAll: () =>
                    registry.rejectBatch(transfer.conversationId, batchId!),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.of(context).t('transfer.waitingForPeer'),
              style: TextStyle(color: muted),
            ),
            _CancelButton(
              muted: muted,
              onPressed: () => registry.cancelTransfer(transfer.id),
            ),
          ],
        );
      case TransferState.accepted:
      case TransferState.transferring:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _TransferProgress(transfer: transfer, muted: muted),
            _CancelButton(
              muted: muted,
              onPressed: () => registry.cancelTransfer(transfer.id),
            ),
          ],
        );
      case TransferState.complete:
        final incoming = transfer.direction == TransferDirection.incoming;
        final savedPath = transfer.localPath;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompletedImagePreview(transfer: transfer, onBubble: onBubble),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: context.chat.online,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    incoming
                        ? S.of(context).t('transfer.savedTo', {
                            'path':
                                savedPath ?? S.of(context).t('transfer.disk'),
                          })
                        : S.of(context).t('transfer.sent'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            if (incoming && savedPath != null && NativeOpen.isSupported)
              _ReceivedActions(path: savedPath, color: onBubble)
            else if (incoming && savedPath != null && _isMobile)
              _ShareReceived(path: savedPath, color: onBubble),
          ],
        );
      case TransferState.rejected:
        return Text(
          S.of(context).t('transfer.declined'),
          style: TextStyle(color: muted),
        );
      case TransferState.cancelled:
        return Text(
          S.of(context).t('transfer.cancelled'),
          style: TextStyle(color: muted),
        );
      case TransferState.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                S.of(context).t('transfer.failed', {
                  'error': _transferErrorText(S.of(context), transfer),
                }),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: muted),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _RetryButton(
              muted: muted,
              onPressed: () => registry.retryTransfer(transfer.id),
            ),
          ],
        );
    }
  }
}

// classifyTransferError 키워드를 문구로 번역함. 원본 예외 문자열은 절대 렌더 안 함
// 공간 부족은 필요한 크기와 다음 행동(데스크톱은 재시도하면 다른 폴더를 고름)을 붙임
String _transferErrorText(S s, FileTransfer t) => switch (t.error) {
  'diskFull' => s.t(
    _isMobile ? 'transfer.errorDiskFull' : 'transfer.errorDiskFullDesktop',
    {'size': formatBytes(t.totalBytes)},
  ),
  'network' => s.t('transfer.errorNetwork'),
  'rejected' => s.t('transfer.errorRejected'),
  'tampered' => s.t('transfer.errorTampered'),
  'cancelled' => s.t('transfer.errorCancelled'),
  'insecureLink' => s.t('transfer.errorInsecureLink'),
  _ => s.t('transfer.unknownError'),
};
