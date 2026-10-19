part of '../message_list.dart';

extension _MessageListView on _MessageListState {
  Widget _buildList(BuildContext context) {
    if (widget.messages.isEmpty && _burning.isEmpty && !widget.peerTyping) {
      return EmptyState(
        art: EmptyStateArt.bubbles,
        title: S.of(context).t('empty.messagesTitle'),
        body: S.of(context).t('empty.messagesBody'),
      );
    }
    final liveIds = {...widget.messages.map((m) => m.id), ..._burning.keys};
    _rowKeys.removeWhere((id, _) => !liveIds.contains(id));

    final entries = _buildEntries();
    final typingRow = widget.peerTyping ? 1 : 0;
    return Stack(
      children: [
        CallbackShortcuts(
          bindings: _scrollKeys,
          child: Focus(
            focusNode: _listFocus,
            // 데스크톱은 스크롤 동작이 스크롤바를 붙이고, 폰은 여기서 붙임 (스크롤할 때만 보임)
            child: _mobileScrollbar(
              context,
              LayoutBuilder(
                // 넓은 창에선 말풍선을 가운데 열로 모으고 스크롤 영역은 전폭 그대로
                builder: (context, box) => ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  physics: listPhysics,
                  padding: EdgeInsets.symmetric(
                    horizontal: readableSide(box.maxWidth, kChatColumnWidth),
                    vertical: AppSpacing.sm,
                  ),
                  itemCount: entries.length + typingRow,
                  itemBuilder: (context, index) {
                    if (typingRow == 1 && index == 0) {
                      return const TypingDots();
                    }
                    final entryIndex = entries.length - 1 - (index - typingRow);
                    final entry = entries[entryIndex];
                    return switch (entry) {
                      _MessageEntry(:final message) => KeyedSubtree(
                        key: _rowKeys.putIfAbsent(message.id, GlobalKey.new),
                        child: _maybeHighlight(
                          message.id,
                          Align(
                            alignment: message.isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: MessageBubble(
                              message: message,
                              joinsPrevious:
                                  entryIndex > 0 &&
                                  _joins(entries[entryIndex - 1], entry),
                              joinsNext:
                                  entryIndex + 1 < entries.length &&
                                  _joins(entry, entries[entryIndex + 1]),
                              onReply: widget.onReply,
                              onJumpToMessage: _jumpToMessage,
                              animateIn: _seen.add(message.id),
                            ),
                          ),
                        ),
                      ),
                      _GhostEntry(:final ghost) => Align(
                        alignment: ghost.mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: _BurnGhost(size: ghost.size),
                      ),
                      _SeparatorEntry(:final label) => _Separator(label),
                    };
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          // 숨긴 동안엔 Tab 칸에서도 빠짐 (안 보이는 칸이 생기지 않게)
          child: ExcludeFocus(
            excluding: !_showJump,
            child: IgnorePointer(
              ignoring: !_showJump,
              child: AnimatedOpacity(
                opacity: _showJump ? 1 : 0,
                duration: motionDuration(
                  context,
                  const Duration(milliseconds: 150),
                ),
                child: PressScale(
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: S.of(context).t('a11y.jumpToLatest'),
                    onPressed: () {
                      AppHaptics.lightImpact();
                      _toBottom();
                    },
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileScrollbar(BuildContext context, Widget list) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS ||
        TargetPlatform.android => Scrollbar(controller: _scroll, child: list),
        _ => list,
      };
}

// 같은 발신자가 5분 안에 이어 보낸 메시지만 한 묶음으로 봄
// 날짜/안 읽음 구분선과 시스템 알림은 묶지 않고, 반응 칩이 달린 말풍선은 칩이 사이에 끼어 묶음을 끊음
// 인증된 ID가 없을 때만 별칭으로 비교함
bool _joins(_Entry before, _Entry after) {
  if (before is! _MessageEntry || after is! _MessageEntry) return false;
  final a = before.message;
  final b = after.message;
  final gap = b.createdAt.difference(a.createdAt);
  return a.kind != MessageKind.system &&
      a.reactions.isEmpty &&
      b.kind != MessageKind.system &&
      a.conversationId == b.conversationId &&
      a.direction == b.direction &&
      (a.senderPeerId ?? a.senderAlias) == (b.senderPeerId ?? b.senderAlias) &&
      !gap.isNegative &&
      gap <= const Duration(minutes: 5);
}
