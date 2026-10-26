part of '../chat_room_screen.dart';

// 방 중계·오프라인·미검증 배너 묶음. 아주 큰 글씨(3배)에선 배너만으로 화면을 다 먹어 메시지 목록이 0이 되고
// 입력창이 잘려서, 묶음 높이를 maxHeight(입력창 위 남은 높이의 30%)로 막고 넘치면 안에서 스크롤함
class _ChatBanners extends StatelessWidget {
  const _ChatBanners({
    required this.maxHeight,
    required this.conversation,
    required this.registry,
    required this.onShowSas,
  });

  final double maxHeight;
  final Conversation conversation;
  final LinkRegistry registry;
  final VoidCallback onShowSas;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Column(
          children: [
            if (conversation.isRoom) const RoomRelayBanner(),
            if (conversation.isRoom &&
                conversation.transport == PeerTransport.app)
              RoomIntegrityBanner(
                book: registry.store.roomIntegrity,
                conversationId: conversation.id,
              ),
            AnimatedSize(
              duration: motionDuration(
                context,
                const Duration(milliseconds: 200),
              ),
              child: !conversation.online
                  ? OfflineBanner(
                      blocked: conversation.blocked,
                      onUnblock: () => registry.unblockPeer(conversation.id),
                      onReconnect:
                          conversation.isRoom && conversation.hostAlias == null
                          ? null
                          : () => registry.reconnect(conversation.id),
                    )
                  : const SizedBox.shrink(),
            ),
            AnimatedSize(
              duration: motionDuration(
                context,
                const Duration(milliseconds: 200),
              ),
              child:
                  (conversation.isRoom
                      ? conversation.members.values.any((m) => !m.verified)
                      : conversation.secure && !conversation.verified)
                  ? UnverifiedBanner(
                      conversation: conversation,
                      onTap: onShowSas,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
