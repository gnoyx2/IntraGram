part of '../chat_room_screen.dart';

mixin _ChatRoomScaffold
    on
        _ChatRoomScreenStateBase,
        _ChatRoomSearch,
        _ChatRoomDialogs,
        _ChatRoomDragDrop {
  PreferredSizeWidget _appBar(
    Conversation conversation, {
    required bool vaultOn,
  }) {
    return AppBar(
      toolbarHeight: AppType.toolbarHeight(context),
      titleSpacing: 0,
      title: _searching
          ? TextField(
              enableIMEPersonalizedLearning: false,
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: S.of(context).t('search.inChat'),
                border: InputBorder.none,
              ),
              onChanged: _runSearch,
            )
          : ChatTitle(conversation: conversation),
      actions: _searching
          ? [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    _hits.isEmpty ? '0/0' : '${_hitIndex + 1}/${_hits.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: S.of(context).t('search.previousHit'),
                onPressed: _hits.length < 2 ? null : () => _moveHit(-1),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: S.of(context).t('search.nextHit'),
                onPressed: _hits.length < 2 ? null : () => _moveHit(1),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: S.of(context).t('search.close'),
                onPressed: _closeSearch,
              ),
            ]
          : [
              if (conversation.isRoom
                  ? conversation.members.isNotEmpty
                  : conversation.secure && conversation.sas != null)
                SasButton(
                  conversation: conversation,
                  onTap: () => _showSas(conversation),
                ),
              TtlMenu(conversation: conversation, registry: _registry),
              ChatOverflowMenu(
                conversation: conversation,
                registry: _registry,
                onAddPeople: () =>
                    showAddPeopleSheet(context, ref, widget.conversationId),
                onEndConversation: _endConversation,
                onSearch: _openSearch,
                onToggleKeep: vaultOn && !conversation.isRoom
                    ? () => ref
                          .read(inMemoryStoreProvider)
                          .setVaultOptOut(
                            widget.conversationId,
                            value: !conversation.vaultOptOut,
                          )
                    : null,
              ),
            ],
    );
  }

  Widget _body(String? replyPreview) {
    // 자체 watch로 감싸서 online/verified/peerTyping 등 conversation 필드 변화가
    // build 전체를 다시 돌리지 않게 함 (앱바와 독립된 형제 리빌드 스코프)
    return Consumer(
      builder: (context, ref, _) {
        final conversation = ref.watch(
          conversationProvider(widget.conversationId),
        );
        if (conversation == null) return const SizedBox.shrink();
        return Column(
          children: [
            _ChatBanners(
              conversation: conversation,
              registry: _registry,
              onShowSas: () => _showSas(conversation),
            ),
            Expanded(
              child: GestureDetector(
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
              ),
            ),
            SafeArea(
              top: false,
              child: ChatInput(
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
            ),
          ],
        );
      },
    );
  }
}

// 앱바를 독립 watch 스코프로 감싸 conversation 필드가 바뀌어도 앱바만 갱신되게 함
// (build 전체나 메시지 리스트는 안 건드림)
class _ChatAppBarScope extends ConsumerWidget implements PreferredSizeWidget {
  const _ChatAppBarScope({
    required this.conversationId,
    required this.builder,
    required this.toolbarHeight,
  });

  final String conversationId;
  final PreferredSizeWidget Function(
    Conversation conversation, {
    required bool vaultOn,
  })
  builder;
  final double toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref.watch(conversationProvider(conversationId));
    final vaultOn = ref.watch(vaultSettingsProvider.select((s) => s.enabled));
    if (conversation == null) return AppBar();
    return builder(conversation, vaultOn: vaultOn);
  }
}

// 첫 메시지 로드 중 빈 스피너 대신 실제 레이아웃(좌우 번갈아, 들쭉날쭉한 폭)을 흉내낸
// 자리표시자. 정적 이미지라 reduce-motion과 무관함
class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  static const _widths = [0.55, 0.35, 0.65, 0.42, 0.58, 0.3];

  @override
  Widget build(BuildContext context) {
    final chat = context.chat;
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < _widths.length; i++)
          Align(
            alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: _widths[i],
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                height: 36,
                decoration: BoxDecoration(
                  color: (i.isEven ? chat.bubbleTheirs : chat.bubbleMine)
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
