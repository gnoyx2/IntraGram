part of '../message_bubble.dart';

// 사칭·중계 가능성을 알리는 줄은 경고색 + 아이콘 (색만으로 구분하지 않음)
const Set<SystemEventKind> _warningEvents = {
  SystemEventKind.sasMismatch,
  SystemEventKind.peerMismatch,
};

class _SystemMessageBubble extends StatelessWidget {
  const _SystemMessageBubble({required this.message});

  final EphemeralMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final warning = _warningEvents.contains(message.systemEvent?.kind);
    final ink = warning ? scheme.onErrorContainer : scheme.onInverseSurface;
    final text = Text(
      message.systemEvent != null
          ? S.of(context).describe(message.systemEvent!)
          : (message.text ?? ''),
      style: textTheme.labelSmall?.copyWith(color: ink),
    );
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          // inverse-surface 페어: 다크 모드에서도 캔버스와 무관하게 스스로 대비를 유지함
          color: warning ? scheme.errorContainer : scheme.inverseSurface,
          borderRadius: BorderRadius.circular(
            warning ? AppRadius.md : AppRadius.pill,
          ),
        ),
        child: warning
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: ink),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(child: text),
                ],
              )
            : text,
      ),
    );
  }
}
