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
        if (value == 'audit') {
          unawaited(
            showAuditProofSheet(
              context,
              registry.store.evidence,
              registry.identity,
            ),
          );
        } else if (value == 'auto') {
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
        PopupMenuItem<String>(value: 'audit', child: Text(s.t('audit.title'))),
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
        // 방 파일은 늘 물어봄 (레지스트리도 미검증 대화의 자동 수락은 무시함)
        if (!conversation.isRoom)
          PopupMenuItem<String>(
            value: 'auto',
            enabled: conversation.verified,
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
      builder: (dialogContext) => AppAlertDialog(
        cupertino: cupertino,
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

// CheckedPopupMenuItem은 내부 ListTile로 그려서 다른 항목과 글자 간격이 달라짐: 평범한 항목에 체크 아이콘만 직접 그림
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
