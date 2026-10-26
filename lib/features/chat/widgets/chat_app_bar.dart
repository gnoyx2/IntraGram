import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart' show SecurityException;
import 'package:intragram/features/chat/audit_proof_sheet.dart';
import 'package:intragram/features/home/connect_failure.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'org_credential_badge.dart';

part 'chat_app_bar/overflow_menu.dart';
part 'chat_app_bar/sas_button.dart';
part 'chat_app_bar/offline_banner.dart';
part 'chat_app_bar/ttl_menu.dart';

class ChatTitle extends StatelessWidget {
  const ChatTitle({required this.conversation, super.key});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final chat = context.chat;
    final s = S.of(context);
    final String status;
    Color statusColor = Theme.of(context).colorScheme.onSurfaceVariant;

    String people(int n) =>
        s.plural(n, one: s.t('chat.person'), other: s.t('chat.people'));

    if (conversation.isRoom) {
      if (conversation.hostAlias == null) {
        // 브라우저 게스트 방은 LAN 구간이 평문이라 상태 줄에서도 그걸 말함
        status = s.t(
          conversation.transport == PeerTransport.web
              ? 'chat.status.webGuestRoom'
              : 'chat.status.youHost',
          {'people': people(conversation.memberCount)},
        );
      } else {
        final who = conversation.memberCount > 0
            ? s.t('chat.withCount', {
                'who': conversation.hostAlias!,
                'people': people(conversation.memberCount),
              })
            : conversation.hostAlias!;
        status = s.t('chat.status.viaHost', {'who': who});
      }
    } else if (!conversation.online) {
      status = s.t('chat.status.offline');
    } else if (conversation.peerTyping) {
      status = s.t('chat.status.typing');
      statusColor = Theme.of(context).colorScheme.tertiary;
    } else if (conversation.secure) {
      final pending = conversation.localVerified && !conversation.verified;
      status = conversation.verified
          ? s.t('chat.status.verified')
          : pending
          ? s.t('chat.status.pending')
          : s.t('chat.status.encrypted');
      statusColor = conversation.verified
          ? Theme.of(context).colorScheme.tertiary
          : chat.burn;
    } else {
      status = s.t('chat.status.connecting');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 제목 옆엔 아이콘을 안 붙임: 보안 상태는 옆 SasButton 방패 하나로만 보여 줌
        Text(
          s.title(conversation),
          style: Theme.of(context).textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // 큰 글씨에서 잘리면 길게 누르거나 마우스를 올려 전문을 봄 (스크린 리더는 Text 전문을 이미 읽어서 툴팁은 뺌)
        Tooltip(
          message: status,
          excludeFromSemantics: true,
          child: Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: statusColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// 암호화됐지만 미검증인 대화에서만 뜸. 나만 확인하고 상대 확인을 기다리는 중이면 대기 문구
class UnverifiedBanner extends StatelessWidget {
  const UnverifiedBanner({
    required this.conversation,
    required this.onTap,
    super.key,
  });

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chat = context.chat;
    // 방은 멤버마다 상태가 달라서 대기 문구를 안 씀 (누가 대기 중인지는 멤버 목록에서 봄).
    // 멤버 쪽은 호스트 한 명뿐이라 그 슬롯이 대기 중이면 같은 문구
    final host = conversation.members.length == 1
        ? conversation.members.values.single
        : null;
    final pending = conversation.isRoom
        ? (host != null && host.localVerified && !host.verified)
        : conversation.localVerified;
    return Semantics(button: true, child: _banner(context, chat, pending));
  }

  Widget _banner(BuildContext context, ChatColors chat, bool pending) {
    return Material(
      color: chat.burn.withValues(alpha: 0.14),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                pending ? Icons.pending : Icons.gpp_maybe,
                size: MediaQuery.textScalerOf(context).scale(18),
                color: chat.burn,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  pending
                      ? S.of(context).t('chat.unverifiedBannerPending')
                      : S.of(context).t('chat.unverifiedBanner'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: MediaQuery.textScalerOf(context).scale(18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 방은 호스트가 풀어서 중계하고 파일은 기기끼리 평문이라 종단 간 암호화가 아님을 늘 보여 줌
class RoomRelayBanner extends StatelessWidget {
  const RoomRelayBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: MediaQuery.textScalerOf(context).scale(18),
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                S.of(context).t('chat.relayBanner'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
