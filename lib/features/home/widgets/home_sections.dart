import 'package:flutter/material.dart';

import 'package:intragram/core/app_settings.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/tokens.dart';

// 서버를 못 띄운 이유(server.problem)를 번역해서 (제목, 본문)으로 돌려줌. 포털 시트도 같은 문구를 씀
(String, String) serverProblemText(S s, ServerState server) =>
    switch (server.problem) {
      ServerProblem.localNetworkDenied => (
        s.t('server.localNetworkDeniedTitle'),
        s.t('server.localNetworkDenied'),
      ),
      ServerProblem.notPrivate => (
        s.t('server.notPrivateTitle'),
        s.t('server.notPrivate', {'address': server.address ?? '?'}),
      ),
      ServerProblem.failed => (s.t('server.failedTitle'), s.t('server.failed')),
      _ => (s.t('home.serverErrorHint'), s.t('server.noNetwork')),
    };

// 서버 시작 실패 배너. Wi-Fi가 이미 있는데 바인딩만 실패한 경우도 있어서 재시도 버튼도 둠
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({required this.server, this.onRetry, super.key});

  final ServerState server;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, message) = serverProblemText(S.of(context), server);
    final s = S.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
                // 원문 예외는 헤드라인 대신 '자세히 보기' 안에 둠 (복사 가능)
                if (server.problem == ServerProblem.failed &&
                    server.error != null)
                  _RawError(server.error!, color: scheme.onErrorContainer),
                if (server.problem == ServerProblem.localNetworkDenied)
                  TextButton(
                    onPressed: () => openSettings(SettingsPane.localNetwork),
                    child: Text(s.t('settings.open')),
                  ),
              ],
            ),
          ),
          if (onRetry != null &&
              server.problem != ServerProblem.localNetworkDenied)
            TextButton(onPressed: onRetry, child: Text(s.t('common.retry'))),
        ],
      ),
    );
  }
}

class _RawError extends StatefulWidget {
  const _RawError(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  State<_RawError> createState() => _RawErrorState();
}

class _RawErrorState extends State<_RawError> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: widget.color),
          onPressed: () => setState(() => _open = !_open),
          child: Text(s.t(_open ? 'error.hideDetail' : 'error.showDetail')),
        ),
        if (_open)
          SelectableText(
            widget.text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: widget.color),
          ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {this.trailing, super.key});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 스크린 리더가 구역 제목으로 건너뛸 수 있게 헤딩으로 표시함
          final title = Semantics(
            header: true,
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          );
          if (trailing != null && constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: AppSpacing.xxs),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
            );
          }
          return Row(
            spacing: AppSpacing.sm,
            children: [
              Expanded(child: title),
              ?trailing,
            ],
          );
        },
      ),
    );
  }
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
