part of '../chat_room_screen.dart';

mixin _ChatRoomDialogs on _ChatRoomScreenStateBase {
  // 보관 on/off와 무관하게 링크를 끊고 대화를 지움
  Future<void> _endConversation() async {
    final navigator = Navigator.of(context);
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(s.t('chat.endConversation')),
        content: Text(s.t('chat.endBody')),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: s.t('common.cancel'),
          ),
          AdaptiveDialogAction(
            cupertino: cupertino,
            emphasis: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: s.t('chat.endButton'),
          ),
        ]),
      ),
    );
    if (ok != true) return;
    await endConversation(ref, widget.conversationId);
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _showSas(Conversation conversation) async {
    final store = ref.read(inMemoryStoreProvider);
    if (conversation.isRoom) {
      final peerId = await showRoomMemberListDialog(context, conversation);
      if (peerId == null || !mounted) return;
      // 목록 다이얼로그가 열려 있는 동안 재연결됐을 수 있어 다시 조회함 (캡처해둔 스냅샷을 안 믿음)
      final member = store.conversation(widget.conversationId)?.members[peerId];
      if (member == null) return;
      final expectedSas = member.sas;
      final outcome = await showSasFingerprintDialog(
        context,
        peerAlias: member.alias,
        sas: member.sas,
        localVerified: member.localVerified,
        verified: member.verified,
      );
      if (outcome == SasOutcome.matched) {
        _registry.markRoomMemberVerified(
          widget.conversationId,
          peerId,
          expectedSas: expectedSas,
        );
      } else if (outcome == SasOutcome.mismatched) {
        await _onSasMismatch(memberPeerId: peerId);
      }
      return;
    }
    final fresh = store.conversation(widget.conversationId) ?? conversation;
    final expectedSas = fresh.sas;
    final outcome = await showSasFingerprintDialog(
      context,
      peerAlias: fresh.peerAlias,
      sas: fresh.sas,
      localVerified: fresh.localVerified,
      verified: fresh.verified,
    );
    if (outcome == SasOutcome.matched) {
      _registry.markVerified(widget.conversationId, expectedSas: expectedSas);
    } else if (outcome == SasOutcome.mismatched) {
      await _onSasMismatch();
    }
  }

  // 링크를 먼저 끊고(더 보내지 않게) 무엇을 해야 하는지 알려 줌. 대화 기록은 남겨 둠
  Future<void> _onSasMismatch({String? memberPeerId}) async {
    await _registry.reportSasMismatch(
      widget.conversationId,
      memberPeerId: memberPeerId,
    );
    if (!mounted) return;
    final s = S.of(context);
    final cupertino = isCupertinoDialog(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        icon: const Icon(Icons.gpp_bad_outlined),
        title: Text(s.t('sas.mismatchTitle')),
        content: Text(s.t('sys.sasMismatch')),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: cupertino,
            emphasis: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: s.t('common.close'),
          ),
        ]),
      ),
    );
  }
}
