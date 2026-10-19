part of '../chat_app_bar.dart';

class SasButton extends StatelessWidget {
  const SasButton({required this.conversation, required this.onTap, super.key});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chat = context.chat;
    // 방은 멤버마다 독립된 SAS 세션이라 "전원 검증"일 때만 초록, 한 명이라도 안 됐으면(대기중 포함) 앰버
    final allVerified = conversation.isRoom
        ? conversation.members.values.every((m) => m.verified)
        : conversation.verified;
    final pending = conversation.isRoom
        ? !allVerified &&
              conversation.members.values.any(
                (m) => m.localVerified && !m.verified,
              )
        : conversation.localVerified && !conversation.verified;
    final tooltip = allVerified
        ? S.of(context).t('chat.sasVerified')
        : pending
        ? S.of(context).t('chat.sasPending')
        : S.of(context).t('chat.sasCheck');
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        allVerified
            ? Icons.gpp_good
            : pending
            ? Icons.pending
            : Icons.gpp_maybe,
        color: allVerified ? chat.online : chat.burn,
      ),
      onPressed: onTap,
    );
  }
}
