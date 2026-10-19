part of '../chat_app_bar.dart';

// SAS가 확인되기 전까지 자동 수락 항목을 회색 처리해서 미검증(사칭 가능) 피어가 탭 없이 파일을 못 떨구게 함
class ChatOverflowMenu extends StatelessWidget {
  const ChatOverflowMenu({
    required this.conversation,
    required this.registry,
    this.onAddPeople,
    this.onEndConversation,
    this.onSearch,
    this.onToggleKeep,
    super.key,
  });

  final Conversation conversation;
  final LinkRegistry registry;

  final VoidCallback? onAddPeople;

  final VoidCallback? onEndConversation;

  final VoidCallback? onSearch;

  // 보관이 켜진 1:1에서만 줌. 이 대화만 파일 저장에서 빼거나 다시 넣음
  final VoidCallback? onToggleKeep;

  @override
  Widget build(BuildContext context) {
    final canAddPeople = onAddPeople != null && conversation.hostAlias == null;
    final s = S.of(context);
    return PopupMenuButton<String>(
      tooltip: s.t('chat.more'),
      onSelected: (value) {
        if (value == 'auto') {
          registry.setAutoAcceptFiles(
            conversation.id,
            enabled: !conversation.autoAcceptFiles,
          );
        } else if (value == 'search') {
          onSearch?.call();
        } else if (value == 'add') {
          onAddPeople?.call();
        } else if (value == 'end') {
          onEndConversation?.call();
        } else if (value == 'block') {
          unawaited(_confirmBlock(context));
        } else if (value == 'unblock') {
          registry.unblockPeer(conversation.id);
        } else if (value == 'keep') {
          onToggleKeep?.call();
        }
      },
      itemBuilder: (context) => [
        if (onSearch != null)
          PopupMenuItem<String>(
            value: 'search',
            child: Text(s.t('search.inChat')),
          ),
        if (canAddPeople)
          PopupMenuItem<String>(
            value: 'add',
            child: Text(s.t('chat.addPeople')),
          ),
        PopupMenuItem<String>(
          value: 'auto',
          // 방은 SAS 검증이 없어서(호스트 중계가 신뢰 경계) verified가 영원히 false라서,
          // isRoom도 허용 안 하면 이 토글이 방에서 항상 회색으로 죽음
          enabled: conversation.isRoom || conversation.verified,
          child: _CheckRow(
            label: s.t('chat.autoAcceptFiles'),
            checked: conversation.autoAcceptFiles,
          ),
        ),
        if (onToggleKeep != null)
          PopupMenuItem<String>(
            value: 'keep',
            child: _CheckRow(
              label: s.t('chat.keepOnDevice'),
              checked: !conversation.vaultOptOut,
            ),
          ),
        if (onEndConversation != null)
          PopupMenuItem<String>(
            value: 'end',
            child: Text(s.t('chat.endConversation')),
          ),
        // 증명된 1:1 상대만 차단 (방은 호스트가 멤버를 관리)
        if (!conversation.isRoom && conversation.peerId != null)
          PopupMenuItem<String>(
            value: conversation.blocked ? 'unblock' : 'block',
            child: Text(
              s.t(conversation.blocked ? 'chat.unblock' : 'chat.block'),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmBlock(BuildContext context) async {
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(s.t('chat.blockTitle', {'alias': conversation.peerAlias})),
        content: Text(s.t('chat.blockBody')),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: s.t('common.cancel'),
          ),
          AdaptiveDialogAction(
            cupertino: cupertino,
            emphasis: true,
            destructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: s.t('chat.block'),
          ),
        ]),
      ),
    );
    if (ok == true) await registry.blockPeer(conversation.id);
  }
}

// CheckedPopupMenuItem은 title을 내부 ListTile로 그려서 다른 항목과 자간이 다르게 먹음
// 평범한 PopupMenuItem + 수동 체크 아이콘으로 같은 텍스트 경로를 타게 함
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.checked});

  final String label;
  final bool checked;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: checked,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: checked
              ? const Icon(Icons.done, size: 20)
              : Icon(
                  Icons.close,
                  size: 20,
                  color: Theme.of(context).disabledColor,
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
