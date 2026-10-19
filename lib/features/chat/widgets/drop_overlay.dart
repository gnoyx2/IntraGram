import 'package:flutter/material.dart';

import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/tokens.dart';

// 포인터 투명(IgnorePointer)이라 드롭 이벤트를 안 먹고 desktop_drop이 밑의 DropTarget에 그대로 전달함
// 웹 게스트 포털의 드래그 하이라이트와 같은 언어: 화면 안쪽 액센트 링 + 바깥 글로우
class DropOverlay extends StatelessWidget {
  const DropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Positioned.fill을 여기 안 둠: 호출부가 AnimatedOpacity/FadeTransition으로 감싸는데
    // Positioned는 Stack의 direct child여야 해서 ("Incorrect use of
    // ParentDataWidget") 호출부가
    // 위젯 전체를 Positioned.fill로 감쌈
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
