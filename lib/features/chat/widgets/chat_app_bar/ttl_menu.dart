part of '../chat_app_bar.dart';

// 내가 다음에 보내는 모든 메시지에 적용되는 TTL. 상대의 카운트다운은 상대가 읽을 때 시작됨
class TtlMenu extends StatelessWidget {
  const TtlMenu({
    required this.conversation,
    required this.registry,
    super.key,
  });

  final Conversation conversation;
  final LinkRegistry registry;

  @override
  Widget build(BuildContext context) {
    final active = conversation.outgoingTtlSeconds > 0;
    final s = S.of(context);
    return PopupMenuButton<int>(
      tooltip: s.t('chat.burnTimer'),
      icon: Icon(
        active ? Icons.timer : Icons.timer_outlined,
        color: active ? context.chat.burn : null,
      ),
      initialValue: conversation.outgoingTtlSeconds,
      onSelected: (seconds) => registry.setBurnTimer(conversation.id, seconds),
      itemBuilder: (context) => [
        for (final seconds in kBurnTtlOptions)
          PopupMenuItem<int>(
            value: seconds,
            child: Text(
              seconds == 0
                  ? s.t('chat.timerOff')
                  : s.t('chat.burnAfter', {'n': '$seconds'}),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          enabled: false,
          child: Text(
            s.t('chat.burn24h'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
