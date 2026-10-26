import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intragram/theme/adaptive_layout.dart';

import 'package:intragram/features/home/home_actions.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/home/widgets/home_sections.dart'
    show serverProblemText;
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/tokens.dart';

import 'portal_qr.dart';
import 'portal_sheet_route.dart';

class PortalSheet extends ConsumerWidget {
  const PortalSheet({super.key});

  static Future<void> show(BuildContext context) {
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    return navigator.push(
      PortalSheetRoute(
        barrierLabel: localizations.scrimLabel,
        barrierOnTapHint: localizations.scrimOnTapHint(
          localizations.bottomSheetLabel,
        ),
        modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        child: const PortalSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverControllerProvider);
    final controller = ref.read(serverControllerProvider.notifier);
    final url = server.portalUrl;
    final s = S.of(context);

    final fold = tabletopFold(context);
    final heading = <Widget>[
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
    ];
    final controls = <Widget>[
      if (url != null) ...[
        if (fold == null) PortalQr(url: url),
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
                // 선택 복사는 클립보드 기록·클라우드 제외 표시를 안 거쳐서 입장 토큰(#t=)이 남을 수 있음: 복사는 옆 버튼(OsPrivacy)으로만 함
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
          server.running ? s.t('portal.offNoGuests') : s.t('portal.serverOff'),
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
    ];
    final padding = EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.xs,
      AppSpacing.xl,
      AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
    );
    Widget scroll(List<Widget> children) => SingleChildScrollView(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    if (fold == null) return scroll([...heading, ...controls]);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 모달 시트는 아래에 붙고 이 위젯 위 칸은 드래그 핸들이 차지함: 화면 맨 위에서 떨어진 만큼 접힘선을 옮겨 셈
        final origin =
            MediaQuery.sizeOf(context).height - constraints.maxHeight;
        final top = (fold.bounds.top - origin).clamp(
          0.0,
          constraints.maxHeight,
        );
        final gap = fold.bounds.height.clamp(0.0, constraints.maxHeight - top);
        return SizedBox(
          height: constraints.maxHeight,
          child: Column(
            children: [
              SizedBox(
                height: top,
                child: url == null
                    ? const SizedBox.shrink()
                    : PortalQr(url: url),
              ),
              SizedBox(height: gap),
              Expanded(child: scroll([...heading, ...controls])),
            ],
          ),
        );
      },
    );
  }
}
