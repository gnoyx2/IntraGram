part of '../message_bubble.dart';

// 말풍선 동작을 실제로 하는 곳: 동작 시트(actions.dart)와 스크린 리더 사용자 지정 동작이 같은 길을 씀
extension _MessageBubbleActionRun on MessageBubble {
  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final registry = ref.read(linkRegistryProvider);
    if (action == 'react:more') {
      final picked = await _pickEmoji(context);
      if (picked != null && context.mounted) {
        AppHaptics.selectionClick();
        registry.toggleReaction(message.conversationId, message.id, picked);
      }
      return;
    }
    if (action.startsWith('react:')) {
      AppHaptics.selectionClick();
      registry.toggleReaction(
        message.conversationId,
        message.id,
        action.substring('react:'.length),
      );
      return;
    }
    switch (action) {
      case 'retry':
        registry.resendFailed(message.id);
      case 'reply':
        onReply?.call(message.id);
      case 'copy':
        await OsPrivacy.copySensitive(message.text ?? '');
      case 'delete':
        AppHaptics.mediumImpact();
        _cancelIfPendingFile(registry);
        registry.deleteMessageForEveryone(message.id);
      case 'deleteForMe':
        AppHaptics.mediumImpact();
        _cancelIfPendingFile(registry);
        registry.deleteMessageForMe(message.id);
    }
  }

  // 수락 전인 내 파일 제안 버블을 지우면 상대 쪽 수락/거절 프롬프트도 같이 치움
  // (안 그러면 버블은 사라졌는데 상대는 계속 수락 여부를 물음)
  void _cancelIfPendingFile(LinkRegistry registry) {
    if (message.kind == MessageKind.file && message.transferId != null) {
      registry.cancelTransfer(message.transferId!);
    }
  }

  // 스크린 리더: 동작 시트를 안 열고 말풍선 노드에서 바로 고르는 동작 (시트 항목과 같은 경로)
  Map<CustomSemanticsAction, VoidCallback> _semanticActions(
    BuildContext context,
    WidgetRef ref,
  ) {
    final s = S.of(context);
    void run(String action) => unawaited(_runAction(context, ref, action));
    return {
      if (onReply != null)
        CustomSemanticsAction(label: s.t('msg.reply')): () => run('reply'),
      if (message.kind == MessageKind.text)
        CustomSemanticsAction(label: s.t('msg.copy')): () => run('copy'),
      CustomSemanticsAction(label: s.t('a11y.addReaction')): () =>
          run('react:more'),
      CustomSemanticsAction(label: s.t('msg.deleteForMe')): () =>
          run('deleteForMe'),
      if (message.isMine)
        CustomSemanticsAction(label: s.t('msg.deleteForEveryone')): () =>
            run('delete'),
    };
  }
}
