import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// IgnorePointer로 감싸 드롭 이벤트를 소비하지 않고 하위 DropTarget으로 전달함. 외형은 웹 포털의 드래그 강조 스타일과 통일함
class DropOverlay extends StatelessWidget {
  const DropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Positioned.fill은 호출부에서 적용함. 호출부가 페이드로 감싸므로 내부에 두면 Stack 직계 자식이 아니게 되어 ParentDataWidget 오류가 발생함
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
