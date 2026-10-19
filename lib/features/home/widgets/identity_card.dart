import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/peer_avatar.dart';
import 'device_code_dialog.dart';
import 'rename_identity_dialog.dart';
import 'wifi_info_dialog.dart';

class IdentityCard extends ConsumerWidget {
  const IdentityCard({required this.identity, required this.server, super.key});

  final AppIdentity identity;
  final ServerState server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = context.chat;
    final alias = ref.watch(identityAliasProvider);
    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            PeerAvatar(
              peerId: identity.peerId,
              alias: alias,
              platform: identity.platform,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    onTap: () => _renameIdentity(context, ref, identity),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          // 줄 수를 안 막음: 아주 큰 글씨(3배)에서도 이름이 잘리지 않고 카드가 길어짐
                          child: Text(
                            alias,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.edit,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    server.running
                        ? S.of(context).t('identity.visibleOn', {
                            'host': server.host ?? '',
                            'port': '${server.port}',
                          })
                        : S.of(context).t('identity.serverOffline'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: S.of(context).t('deviceCode.tooltip'),
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: () => showDeviceCodeDialog(
                context,
                host: server.running ? server.host : null,
                port: server.running ? server.port : null,
                peerId: identity.peerId,
              ),
            ),
            IconButton(
              tooltip: S.of(context).t('wifiInfo.title'),
              icon: Icon(
                server.running
                    ? Icons.wifi_tethering
                    : Icons.wifi_tethering_off,
                color: server.running ? chat.online : null,
              ),
              onPressed: () => showWifiInfoDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}

// 빈 문자열로 지우고 확정하면 저장된 이름을 지우고 새 랜덤 이름으로 되돌림 (별도 초기화 버튼 없음)
Future<void> _renameIdentity(
  BuildContext context,
  WidgetRef ref,
  AppIdentity identity,
) async {
  final result = await showDialog<({String alias, bool save})>(
    context: context,
    builder: (_) => RenameIdentityDialog(currentAlias: identity.alias),
  );
  if (result == null) return;

  final notifier = ref.read(identityAliasProvider.notifier);
  if (result.alias.isEmpty) {
    await notifier.resetToRandom();
    return;
  }
  await notifier.rename(result.alias, save: result.save);
}
