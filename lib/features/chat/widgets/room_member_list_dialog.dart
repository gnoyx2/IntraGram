import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/color_schemes.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'package:intragram/widgets/peer_avatar.dart';

const double _kMinRowHeight = 56.0;
const double _kMaxViewportHeight = 320.0;

// 멤버마다 독립된 SAS 세션이라 방 전체가 아니라 한 명씩 확인해야 함 (RoomMember 참고)
// 오프라인 멤버는 살아있는 세션이 없어 선택 불가
Future<String?> showRoomMemberListDialog(
  BuildContext context,
  Conversation conversation,
) {
  final chat = context.chat;
  final s = S.of(context);
  final entries = conversation.members.entries.toList()
    ..sort((a, b) => a.value.alias.compareTo(b.value.alias));
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final textScaler = MediaQuery.textScalerOf(dialogContext);
      // 56px 고정 추정 대신 실제 텍스트 배율을 반영해서, 배율이 커져도 alias가 안 잘리게 함
      final rowHeight = math.max(_kMinRowHeight, textScaler.scale(20) + 32);
      final media = MediaQuery.of(dialogContext);
      final safeAvailableHeight = math.max(
        0.0,
        media.size.height - media.viewInsets.vertical - media.padding.vertical,
      );
      final capped = math.min(_kMaxViewportHeight, safeAvailableHeight * 0.5);
      final contentHeight = entries.isEmpty
          ? rowHeight
          : entries.length * rowHeight;
      final viewportHeight = math.min(contentHeight, capped);
      return AlertDialog.adaptive(
        title: Text(s.t('chat.roomMembersTitle')),
        content: SizedBox(
          width: double.maxFinite,
          height: viewportHeight,
          child: entries.isEmpty
              ? Center(child: Text(s.t('empty.roomMembersTitle')))
              // Cupertino 콘텐츠 위에 Material ListTile을
              // 바로 놓으면 Material 조상을 못 찾아 assert에 걸림
              // transparency 타입으로 감싸 Cupertino 배경 위에서도 렌더되게 함
              : Material(
                  type: MaterialType.transparency,
                  child: ListView.builder(
                    itemExtent: rowHeight,
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final entry = entries[i];
                      final member = entry.value;
                      return _MemberRow(
                        peerId: entry.key,
                        member: member,
                        chat: chat,
                        statusLabel: _statusLabel(s, member),
                        onTap: member.online
                            ? () => Navigator.of(dialogContext).pop(entry.key)
                            : null,
                      );
                    },
                  ),
                ),
        ),
        actions: dialogActions(dialogContext, [
          AdaptiveDialogAction(
            cupertino: isCupertinoDialog(context),
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: s.t('common.cancel'),
          ),
        ]),
      );
    },
  );
}

String _statusLabel(S s, RoomMember member) {
  if (!member.online) return s.t('chat.status.offline');
  if (member.verified) return s.t('chat.status.verified');
  if (member.localVerified) return s.t('chat.status.pending');
  return s.t('chat.status.encrypted');
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.peerId,
    required this.member,
    required this.chat,
    required this.statusLabel,
    required this.onTap,
  });

  final String peerId;
  final RoomMember member;
  final ChatColors chat;
  final String statusLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = !member.online
        ? Icons.wifi_off
        : member.verified
        ? Icons.gpp_good
        : member.localVerified
        ? Icons.pending
        : Icons.gpp_maybe;
    final color = member.online
        ? (member.verified ? chat.online : chat.burn)
        : Theme.of(context).disabledColor;
    // 자식(아바타 기기 이름·제목·툴팁)은 빼고 이 라벨 하나로: 안 그러면 멤버마다 두 번 읽힘
    return Semantics(
      label: '${member.alias}, $statusLabel',
      enabled: member.online,
      button: true,
      onTap: member.online ? onTap : null,
      excludeSemantics: true,
      child: ListTile(
        enabled: member.online,
        leading: PeerAvatar(
          peerId: peerId,
          alias: member.alias,
          platform: member.platform,
        ),
        title: Text(member.alias, overflow: TextOverflow.ellipsis),
        trailing: Tooltip(
          message: statusLabel,
          child: ExcludeSemantics(child: Icon(icon, color: color)),
        ),
        onTap: onTap,
      ),
    );
  }
}
