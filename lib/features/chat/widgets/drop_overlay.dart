import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// IgnorePointer라 드롭 이벤트를 안 먹고 밑의 DropTarget으로 그대로 감. 모양은 웹 포털의 드래그 강조와 맞춤
class DropOverlay extends StatelessWidget {
  const DropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Positioned.fill은 호출부가 씌움: 호출부가 페이드로 감싸서 여기 두면 Stack의 직계 자식이 아니게 됨
    // (Incorrect use of ParentDataWidget)
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: scheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: scheme.outlineVariant,
              width: AppBorder.hairline,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_download, size: 32, color: scheme.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(S.of(context).t('drop.hint')),
            ],
          ),
        ),
      ),
    );
  }
}
