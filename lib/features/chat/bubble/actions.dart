part of '../message_bubble.dart';

extension _MessageBubbleActions on MessageBubble {
  // at이 있으면(우클릭·키보드) 그 자리 메뉴, 없으면(길게 누르기) 바텀 시트
  Future<void> _promptActions(
    BuildContext context,
    WidgetRef ref, [
    Offset? at,
  ]) async {
    AppHaptics.lightImpact();
    final isText = message.kind == MessageKind.text;
    final canRetry = message.delivery == DeliveryState.failed && isText;

    final action = await showActionMenu<String>(
      context,
      at: at,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            // 칸을 같은 폭으로 나눠서 좁은 화면(이모지 폰트 폭이 큰 Android, 큰 디스플레이
            // 크기)에서도 줄이 안 넘치고 칸 전체가 탭 영역이 됨
            child: Row(
              children: [
                for (final emoji in kQuickReactions)
                  _quickReaction(
                    sheetContext,
                    label: S.of(sheetContext).t('a11y.reactWith', {
                      'emoji': emoji,
                    }),
                    result: 'react:$emoji',
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                _quickReaction(
                  sheetContext,
                  label: S.of(sheetContext).t('a11y.addReaction'),
                  result: 'react:more',
                  child: const Icon(Icons.add_reaction_outlined, size: 24),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (canRetry)
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(S.of(sheetContext).t('msg.retry')),
              onTap: () => Navigator.of(sheetContext).pop('retry'),
            ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: Text(S.of(sheetContext).t('msg.reply')),
            onTap: () => Navigator.of(sheetContext).pop('reply'),
          ),
          if (isText)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(S.of(sheetContext).t('msg.copy')),
              onTap: () => Navigator.of(sheetContext).pop('copy'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(S.of(sheetContext).t('msg.deleteForMe')),
            onTap: () => Navigator.of(sheetContext).pop('deleteForMe'),
          ),
          // 남의 메시지는 내 쪽에서만 지움 (상대 쪽 사본은 쓴 사람만 지울 수 있고 받는 쪽이 거부함)
          if (message.isMine)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(S.of(sheetContext).t('msg.deleteForEveryone')),
              subtitle: Text(S.of(sheetContext).t('msg.deleteForEveryoneSub')),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    await _runAction(context, ref, action);
  }

  // 자유 입력 대신 탭으로만 고름: IME 조합 중 onChanged에서 pop하면 TextField가 내려가며 assertion으로 앱이 죽었음
  Widget _quickReaction(
    BuildContext sheetContext, {
    required String label,
    required String result,
    required Widget child,
  }) => Expanded(
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () => Navigator.of(sheetContext).pop(result),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(child: child),
        ),
      ),
    ),
  );

  Future<String?> _pickEmoji(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(sheetContext).pop(),
          },
          child: Focus(
            autofocus: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          S.of(sheetContext).t('msg.pickEmojiHint'),
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: S.of(sheetContext).t('viewer.close'),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // 48dp 히트 타겟 기준 열 수 (1..7로 clamp)
                      final columns = (constraints.maxWidth / 48).floor().clamp(
                        1,
                        7,
                      );
                      final media = MediaQuery.of(sheetContext);
                      final maxGridHeight =
                          (media.size.height -
                                  media.viewInsets.bottom -
                                  media.padding.vertical -
                                  160)
                              .clamp(120.0, 280.0);
                      return SizedBox(
                        height: maxGridHeight,
                        child: GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                              ),
                          itemCount: kExtendedReactions.length,
                          itemBuilder: (context, index) {
                            final emoji = kExtendedReactions[index];
                            return Semantics(
                              button: true,
                              label: S.of(sheetContext).t('a11y.reactWith', {
                                'emoji': emoji,
                              }),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.xs,
                                ),
                                onTap: () =>
                                    Navigator.of(sheetContext).pop(emoji),
                                child: Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
