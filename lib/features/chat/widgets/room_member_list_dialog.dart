import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/org_auth.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/color_schemes.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';
import 'package:intragram/widgets/peer_avatar.dart';
import 'org_credential_badge.dart' show orgStatusLabel;

const double _kMinRowHeight = 56.0;
const double _kMaxViewportHeight = 320.0;

// 멤버마다 SAS 세션이 따로라 방 전체가 아니라 한 명씩 확인함 (RoomMember 참고). 오프라인 멤버는 세션이 없어서 못 고름
Future<String?> showRoomMemberListDialog(
  BuildContext context,
  Conversation conversation, {
  OrgCredentialBook? orgCredentials,
}) {
  final chat = context.chat;
  final s = S.of(context);
  final entries = conversation.members.entries.toList()
    ..sort((a, b) => a.value.alias.compareTo(b.value.alias));
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final textScaler = MediaQuery.textScalerOf(dialogContext);
      // 고정 56px 대신 실제 글자 배율을 반영해서 큰 글씨에서도 alias가 안 잘림
      final rowHeight = math.max(
        _kMinRowHeight,
        textScaler.scale(20) + (orgCredentials == null ? 32 : 64),
      );
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
      return AppAlertDialog(
        cupertino: isCupertinoDialog(context),
        title: Text(s.t('chat.roomMembersTitle')),
        content: SizedBox(
          width: double.maxFinite,
          height: viewportHeight,
          child: entries.isEmpty
              ? Center(child: Text(s.t('empty.roomMembersTitle')))
              // Cupertino 대화상자 안엔 Material 조상이 없어서 ListTile이 assert에 걸림: 투명 Material로 감쌈
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
                        orgCredentials: orgCredentials,
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
    this.orgCredentials,
    required this.member,
    required this.chat,
    required this.statusLabel,
    required this.onTap,
  });

  final String peerId;
  final OrgCredentialBook? orgCredentials;
  final RoomMember member;
  final ChatColors chat;
  final String statusLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final book = orgCredentials;
    if (book == null) return _content(context, null);
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) => _content(
        context,
        orgStatusLabel(S.of(context), book.statusOf(peerId)),
      ),
    );
  }

  Widget _content(BuildContext context, String? orgLabel) {
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
    // 자식(아바타의 기기 이름·제목·툴팁)은 빼고 이 라벨 하나만 읽힘 (안 그러면 멤버마다 두 번 읽힘)
    return Semantics(
      label:
          '${member.alias}, $statusLabel${orgLabel == null ? '' : ', $orgLabel'}',
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
        subtitle: orgLabel == null
            ? null
            : Text(orgLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Tooltip(
          message: statusLabel,
          child: ExcludeSemantics(child: Icon(icon, color: color)),
        ),
        onTap: onTap,
      ),
    );
  }
}
