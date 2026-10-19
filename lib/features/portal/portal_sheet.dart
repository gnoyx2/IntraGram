import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:intragram/features/home/home_actions.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/peer_code.dart';
import 'package:intragram/features/home/widgets/home_sections.dart'
    show serverProblemText;
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/tokens.dart';

class PortalSheet extends ConsumerWidget {
  const PortalSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const PortalSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverControllerProvider);
    final controller = ref.read(serverControllerProvider.notifier);
    final url = server.portalUrl;
    final s = S.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      // isScrollControlled 시트라 낮은 화면(작은 폰, 랜드스케이프)이나 내용이 늘어날 때 넘칠 수 있어서 스크롤되게 함
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.t('home.guestPortal'),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              s.t('portal.body'),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (url != null) ...[
              Center(
                // 흰 배경은 스캐너 가독성 때문에 의도적으로 유지. 다크 표면에서 얼룩이 아니라 카드로 읽히게 그림자를 줌
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Semantics(
                    label: s.t('a11y.qrCodeUrl'),
                    child: QrImageView(
                      // 앱이 찍으면 이 기기 신원으로 고정됨. 브라우저는 #t만 읽고 p는 무시
                      data: portalCodeWithPeer(
                        url,
                        ref.read(appIdentityProvider).peerId,
                      ),
                      version: QrVersions.auto,
                      size: 208,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Center(
                child: Text(
                  s.t('qr.whiteBackgroundNote'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    // 두 줄로 접히면 42pt라 iOS 터치 영역(44pt)에 모자라서 높이 하한을 둠
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      // 고르기 복사는 클립보드 기록·클라우드 제외를 안 거쳐서 입장 코드(#t=)가 남을 수 있음:
                      // 복사는 옆 버튼(OsPrivacy)으로만
                      child: Text(
                        url,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: s.t('portal.copyUrl'),
                    onPressed: () async {
                      await OsPrivacy.copySensitive(url);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.t('portal.urlCopied'))),
                        );
                      }
                    },
                  ),
                ],
              ),
            ] else if (server.problem != null) ...[
              Text(
                serverProblemText(s, server).$2,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ] else
              Text(
                server.running
                    ? s.t('portal.offNoGuests')
                    : s.t('portal.serverOff'),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('portal.localServer')),
              subtitle: Text(
                server.running
                    ? s.t('portal.servingOn', {
                        'host': server.host ?? '',
                        'port': '${server.port}',
                      })
                    : s.t('portal.offNoGuests'),
              ),
              value: server.running,
              onChanged: (_) => controller.toggle(),
            ),
            if (server.running) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(s.t('portal.webGuests')),
                subtitle: Text(
                  s.t('portal.webGuestsSub'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: server.portalEnabled,
                onChanged: (value) => controller.setPortalEnabled(value),
              ),
            ],
            if (canScanQr) ...[
              const Divider(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(s.t('portal.scanAnother')),
                onPressed: () => scanConnect(context, ref),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
