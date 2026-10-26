part of '../chat_room_screen.dart';

mixin _ChatRoomBody
    on
        _ChatRoomScreenStateBase,
        _ChatRoomDialogs,
        _ChatRoomDragDrop,
        _ChatRoomSearch {
  Widget _body(String? replyPreview) {
    // 자체 watch로 감싸서 online/verified/peerTyping 등 conversation 필드 변화가
    // build 전체를 다시 돌리지 않게 함 (앱바와 독립된 형제 리빌드 스코프)
    return Consumer(
      builder: (context, ref, _) {
        final conversation = ref.watch(
          conversationProvider(widget.conversationId),
        );
        if (conversation == null) return const SizedBox.shrink();
        final messages = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: FocusScope.of(context).unfocus,
          // 키보드 내리기용이라 메시지 영역 전체가 이름 없는 탭 노드로 읽히지 않게 함
          excludeFromSemantics: true,
          child: Container(
            color: context.chat.canvas,
            child: Consumer(
              builder: (context, ref, _) => ref
                  .watch(roomMessagesProvider(widget.conversationId))
                  .when(
                    loading: () => const _ChatSkeleton(),
                    error: (e, _) => ErrorState(
                      title: S.of(context).t('error.messagesTitle'),
                      action: S.of(context).t('error.messagesAction'),
                      detail: e,
                    ),
                    data: (list) => MessageList(
                      messages: list,
                      unreadOnOpen: _unreadOnOpen,
                      onReply: (id) => setState(() => _replyingTo = id),
                      highlightMessageId: _currentHit,
                      focusMessageId: _currentHit,
                      peerTyping: conversation.peerTyping,
                    ),
                  ),
            ),
          ),
        );
        return _ChatLayout(
          messages: LayoutBuilder(
            builder: (context, box) => Column(
              children: [
                _ChatBanners(
                  maxHeight: box.maxHeight * 0.3,
                  conversation: conversation,
                  registry: _registry,
                  onShowSas: () => _showSas(conversation),
                ),
                Expanded(child: messages),
              ],
            ),
          ),
          input: ChatInput(
            enabled: conversation.online,
            replyPreview: replyPreview,
            onCancelReply: () => setState(() => _replyingTo = null),
            onSend: (text) {
              _registry.sendText(
                widget.conversationId,
                text,
                replyToId: _replyingTo,
              );
              if (_replyingTo != null) setState(() => _replyingTo = null);
            },
            onAttach: _attach,
            onAttachPaths: (paths) =>
                _registry.offerFilesFromPaths(widget.conversationId, paths),
            onSendImage: (bytes) => _registry.offerInlineBytes(
              widget.conversationId,
              'pasted-image.png',
              bytes,
              mime: 'image/png',
            ),
            onSendVoice: (bytes) => _registry.offerInlineBytes(
              widget.conversationId,
              'voice-note.wav',
              bytes,
              mime: 'audio/wav',
              voice: true,
            ),
            onTypingChanged: (active) =>
                _registry.sendTyping(widget.conversationId, active: active),
          ),
        );
      },
    );
  }
}
