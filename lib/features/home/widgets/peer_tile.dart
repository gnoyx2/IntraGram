import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/action_menu.dart';
import 'package:intragram/widgets/keyboard_access.dart';
import 'package:intragram/widgets/peer_avatar.dart';

// 탭하면 다이얼하고 방 엶. 롱프레스는 퀵 전송 단축키: 다이얼 + 클립보드 텍스트 전송 + 방 엶
class PeerTile extends StatelessWidget {
  const PeerTile({
    required this.peer,
    required this.onTap,
    required this.onMenu,
    super.key,
  });

  final PeerDevice peer;
  final VoidCallback onTap;
  // 길게 누르기는 at 없이(바텀 시트), 우클릭·메뉴 키는 그 자리(팝업 메뉴)
  final void Function([Offset? at]) onMenu;

  @override
  Widget build(BuildContext context) {
    final line = peer.detail;
    // 우클릭(데스크톱)도 롱프레스와 같은 액션 시트를 열게 함
    // ListTile엔 secondary-tap 훅이 없어서 GestureDetector로 감쌈
    return CallbackShortcuts(
      bindings: menuKeyBindings(() => onMenu(menuAnchor(context))),
      child: GestureDetector(
        // 우클릭 전용이라 스크린 리더에 이름 없는 '탭' 칸을 만들지 않음 (길게 누르기 동작은 ListTile에 있음)
        excludeFromSemantics: true,
        onSecondaryTapUp: (details) => onMenu(details.globalPosition),
        child: ListTile(
          leading: PeerAvatar(
            peerId: peer.peerId,
            alias: peer.alias,
            platform: peer.platform,
          ),
          title: Text(peer.alias),
          subtitle: peer.hostsRoom
              ? Row(
                  children: [
                    Flexible(
                      child: Text(line, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const _RoomChip(),
                  ],
                )
              : peer.inRoom
              ? Row(
                  children: [
                    Flexible(
                      child: Text(line, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const _InRoomHint(),
                  ],
                )
              : Text(line),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
          onLongPress: onMenu,
        ),
      ),
    );
  }
}

// mDNS inRoom=1(호스트 아닌 멤버) 피어 표시. 멤버는 직접 합류를 못 받아서 눌러보라고 유도하면
// 안 되니 _RoomChip과 일부러 다르게(알약 배지 아님) 순수 정보성으로 그림
class _InRoomHint extends StatelessWidget {
  const _InRoomHint();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.groups_outlined, size: 12, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          S.of(context).t('peerTile.inRoom'),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        S.of(context).t('peerTile.hostingRoom'),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
