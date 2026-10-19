part of '../message_bubble.dart';

// 답장 인용: 3dp 둥근 액센트 막대 + 옅은 틴트 배경 + (파일이면) 둥근 미리보기
class _QuotedStrip extends ConsumerWidget {
  const _QuotedStrip({
    required this.conversationId,
    required this.parentId,
    required this.mine,
    required this.foreground,
    this.onTap,
  });

  final String conversationId;
  final String parentId;
  final bool mine;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final chat = context.chat;
    final parent = ref.watch(
      messageByIdProvider((
        conversationId: conversationId,
        messageId: parentId,
      )),
    );
    final gone = parent == null;
    final transferId = parent?.kind == MessageKind.file
        ? parent?.transferId
        : null;
    final transfer = transferId == null
        ? null
        : ref.watch(transferProvider(transferId));
    final label = switch (parent) {
      null => s.t('common.messageDeleted'),
      _ when parent.kind == MessageKind.file => switch (transfer) {
        null => s.t('common.file'),
        _ when transfer.voice => s.t('transfer.voiceLabel'),
        _ => transfer.fileName,
      },
      _ => parent.text ?? '',
    };
    final ink = chat.accentInk;
    final strip = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs + AppSpacing.xxs),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: mine ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: gone ? foreground.withValues(alpha: 0.35) : ink,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!gone)
                      Text(
                        parent.isMine ? s.t('common.you') : parent.senderAlias,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: foreground,
                        fontStyle: gone ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (transferId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: TransferThumb(transferId: transferId),
              ),
          ],
        ),
      ),
    );
    // 원본이 없으면(소각/삭제) 스크롤해도 갈 데가 없어서 탭을 끔
    if (onTap == null || gone) return strip;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: strip,
    );
  }
}
