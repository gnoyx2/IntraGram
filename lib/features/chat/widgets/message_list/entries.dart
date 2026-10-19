part of '../message_list.dart';

sealed class _Entry {
  const _Entry();
  const factory _Entry.message(EphemeralMessage message) = _MessageEntry;
  const factory _Entry.ghost(_BurnGhostSpec ghost) = _GhostEntry;
  const factory _Entry.separator(String label) = _SeparatorEntry;
}

class _MessageEntry extends _Entry {
  const _MessageEntry(this.message);
  final EphemeralMessage message;
}

// 소각 애니메이션에만 필요한 최소 정보. 원본 내용을 안 들고 있어서 만료 후에도 평문이 위젯 트리에 안 남음
class _GhostEntry extends _Entry {
  const _GhostEntry(this.ghost);
  final _BurnGhostSpec ghost;
}

class _BurnGhostSpec {
  const _BurnGhostSpec({
    required this.id,
    required this.createdAt,
    required this.mine,
    required this.size,
  });

  final String id;
  final DateTime createdAt;
  final bool mine;
  final Size size;
}

class _SeparatorEntry extends _Entry {
  const _SeparatorEntry(this.label);
  final String label;
}

class _Separator extends StatelessWidget {
  const _Separator(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: scheme.outlineVariant,
            width: AppBorder.hairline,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
