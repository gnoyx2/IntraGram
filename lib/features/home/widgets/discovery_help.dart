import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'package:intragram/core/app_settings.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 한참 찾아도 아무도 없을 때 펼쳐 보는 점검표. 원인 대부분(같은 Wi-Fi 아님, 게스트·회사 Wi-Fi의
// 기기 간 차단, iOS·macOS 로컬 네트워크 권한, Windows 방화벽)을 사용자가 직접 확인하게 하고,
// 막힌 망의 유일한 우회인 폰 핫스팟을 알려 줌
class DiscoveryHelp extends StatelessWidget {
  const DiscoveryHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final platform = defaultTargetPlatform;
    final apple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    final windows = platform == TargetPlatform.windows;
    final items = <String>[
      'discoveryHelp.sameWifi',
      'discoveryHelp.appOpen',
      if (apple) 'discoveryHelp.localNetwork',
      if (windows) 'discoveryHelp.firewall',
      'discoveryHelp.hotspot',
      'discoveryHelp.byIp',
    ];
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.help_outline),
        title: Text(s.t('discoveryHelp.title')),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final key in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(s.t(key), style: textTheme.bodyMedium)),
                ],
              ),
            ),
          if ((apple || windows) && canOpenSettings(SettingsPane.localNetwork))
            TextButton(
              onPressed: () => openSettings(SettingsPane.localNetwork),
              child: Text(s.t('settings.open')),
            ),
        ],
      ),
    );
  }
}
