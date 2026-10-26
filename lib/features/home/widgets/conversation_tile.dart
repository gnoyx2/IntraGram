import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/action_menu.dart';
import 'package:intragram/widgets/keyboard_access.dart';
import 'package:intragram/widgets/peer_avatar.dart';

// 미검증 방패(경고색)는 암호화는 됐지만 6자리 코드를 아직 안 맞춘 상태라 중간자를 배제하지 못함. SAS를 맞춰야 초록이 됨
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onMenu,
    this.selected = false,
    super.key,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  // 길게 누르기는 at 없이(바텀 시트), 우클릭·메뉴 키는 그 자리(팝업 메뉴)
  final void Function([Offset? at]) onMenu;

  // 2단 배치에서 오른쪽 창에 열린 대화
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final chat = context.chat;
    final s = S.of(context);
    // ListTile엔 우클릭 훅이 없어서 GestureDetector로 감쌈
    return CallbackShortcuts(
      bindings: menuKeyBindings(() => onMenu(menuAnchor(context))),
      child: GestureDetector(
        // 우클릭 전용이라 스크린 리더에 이름 없는 '탭' 칸을 만들지 않음 (길게 누르기 동작은 ListTile에 있음)
        excludeFromSemantics: true,
        onSecondaryTapUp: (details) => onMenu(details.globalPosition),
        child: ListTile(
          selected: selected,
          leading: PeerAvatar(
            peerId: conversation.peerId ?? conversation.id,
            alias: s.title(conversation),
            platform: conversation.isRoom ? null : conversation.peerPlatform,
          ),
          title: Row(
            children: [
              Flexible(child: Text(s.title(conversation))),
              // 방은 호스트가 평문을 보는 중계라 1:1 방패 대신 허브 아이콘. 초록은 멤버 전원을 맞춰 봤을 때만
              if (conversation.isRoom) ...[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: s.t(
                    _membersVerified
                        ? 'convTile.roomVerified'
                        : 'convTile.roomUnverified',
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    size: 15,
                    color: _membersVerified ? chat.online : chat.burn,
                  ),
                ),
              ] else if (conversation.secure) ...[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message: conversation.verified
                      ? s.t('a11y.secureVerified')
                      : s.t('a11y.secureUnverified'),
                  child: Icon(
                    conversation.verified ? Icons.gpp_good : Icons.gpp_maybe,
                    size: 15,
                    color: conversation.verified ? chat.online : chat.burn,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            _subtitle(s),
            style: TextStyle(
              color: conversation.online
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: conversation.unread > 0
              ? Semantics(
                  label: s.plural(
                    conversation.unread,
                    one: s.t('a11y.unreadOne'),
                    other: s.t('a11y.unreadOther'),
                  ),
                  child: Badge(label: Text('${conversation.unread}')),
                )
              : const Icon(Icons.chevron_right),
          onTap: onTap,
          onLongPress: onMenu,
        ),
      ),
    );
  }

  bool get _membersVerified =>
      conversation.members.isNotEmpty &&
      conversation.members.values.every((m) => m.verified);

  String _subtitle(S s) {
    if (!conversation.online) return s.t('chat.status.offline');
    // 브라우저 게스트 방은 LAN 구간이 평문임
    if (conversation.isRoom && conversation.transport == PeerTransport.web) {
      return s.t('convTile.webGuestRoom');
    }
    if (conversation.isRoom) {
      return s.t('convTile.roomOnline', {
        'people': s.t('chat.people', {'n': '${conversation.memberCount}'}),
      });
    }
    if (conversation.secure) {
      return s.t(
        conversation.verified
            ? 'convTile.verifiedOnline'
            : 'convTile.encryptedOnline',
      );
    }
    return s.t('convTile.platformOnline', {
      'platform': conversation.peerPlatform,
    });
  }
}
