import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 원본 오류는 숨기지만 지우진 않음 (제목으론 안 씀): LAN 앱이라 사용자가 곧 네트워크 관리자인 경우가 많아 펼쳐서 복사할 수 있게 둠
class ErrorState extends StatefulWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.action,
    required this.detail,
    this.onRetry,
  });

  final String title;
  final String action;
  final Object detail;
  final VoidCallback? onRetry;

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final s = S.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.huge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 24,
                  color: scheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                widget.title,
                style: textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.action,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: widget.onRetry,
                  child: Text(s.t('common.retry')),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              TextButton.icon(
                onPressed: () => setState(() => _showDetail = !_showDetail),
                icon: Icon(
                  _showDetail
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  s.t(_showDetail ? 'error.hideDetail' : 'error.showDetail'),
                ),
              ),
              if (_showDetail)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: SelectableText(
                    '${widget.detail}',
                    style: textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
