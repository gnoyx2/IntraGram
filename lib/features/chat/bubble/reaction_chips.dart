part of '../message_bubble.dart';

// Center 없이 Row(min)만 씀: Center는 가로폭을 최대로 늘려서 Wrap 안에서
// 칩 하나가 한 줄을 먹고 세로로 쌓이며 가운데로 떠 보임
// 반응이 없어도 말풍선과 같이 마운트해 둠. 그래야 첫 반응도 새로 붙은 반응으로 잡혀 튀어나옴
class _ReactionChips extends ConsumerStatefulWidget {
  const _ReactionChips({
    required this.message,
    required this.mine,
    this.onAddReaction,
  });

  final EphemeralMessage message;
  final bool mine;
  final VoidCallback? onAddReaction;

  @override
  ConsumerState<_ReactionChips> createState() => _ReactionChipsState();
}

class _ReactionChipsState extends ConsumerState<_ReactionChips> {
  // 직전 위젯에 이미 있던 반응. 마운트 때(채팅 열기, 스크롤 복귀) 있던 칩은 바로 크기 1로 그리고
  // 그 뒤 새로 붙은 반응만 0에서 튀어나옴
  late Set<String> _shown = _emojis(widget.message);

  static Set<String> _emojis(EphemeralMessage message) => {
    for (final set in message.reactions.values) ...set,
  };

  @override
  void didUpdateWidget(_ReactionChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    _shown = _emojis(oldWidget.message);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final mine = widget.mine;
    final onAddReaction = widget.onAddReaction;
    final myPeerId = ref.watch(appIdentityProvider).peerId;
    final counts = <String, int>{};
    for (final set in message.reactions.values) {
      for (final e in set) {
        counts[e] = (counts[e] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    final mineReactions = message.reactions[myPeerId] ?? const <String>{};

    return Padding(
      padding: EdgeInsets.only(
        left: mine ? 0 : AppSpacing.md,
        right: mine ? AppSpacing.md : 0,
      ),
      child: Wrap(
        alignment: mine ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final entry in counts.entries)
            TweenAnimationBuilder<double>(
              key: ValueKey(entry.key),
              tween: Tween(begin: _shown.contains(entry.key) ? 1 : 0, end: 1),
              duration: motionDuration(context, AppMotion.settle),
              curve: Curves.easeOutBack,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: _ReactionChip(
                emoji: entry.key,
                count: entry.value,
                active: mineReactions.contains(entry.key),
                onTap: () => ref
                    .read(linkRegistryProvider)
                    .toggleReaction(
                      message.conversationId,
                      message.id,
                      entry.key,
                    ),
              ),
            ),
          if (onAddReaction != null)
            _ReactionChip(active: false, onTap: onAddReaction),
        ],
      ),
    );
  }
}

// 캡슐 배지. 내가 누른 반응은 액센트 테두리로 강조하고, 탭하면 스프링으로 톡 튀어오름
class _ReactionChip extends StatefulWidget {
  const _ReactionChip({
    this.emoji,
    this.count,
    required this.active,
    required this.onTap,
  });

  final String? emoji;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip>
    with SingleTickerProviderStateMixin {
  // 0을 중심으로 출렁이는 변위. scale = 1 + 변위 (첫 정점 약 1.1)
  late final AnimationController _pop = AnimationController.unbounded(
    vsync: this,
  );

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 600,
    damping: 14,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pop.stop();
      _pop.value = 0;
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  // 반응 추가 칩은 여는 액션 시트(_promptActions)가 햅틱을 울려서 여기선 반응 토글에만 울림
  void _handleTap() {
    if (widget.emoji != null) AppHaptics.selectionClick();
    if (!MediaQuery.disableAnimationsOf(context)) {
      _pop.animateWith(SpringSimulation(_spring, 0, 0, 4));
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active;
    final emoji = widget.emoji;
    final fg = active ? context.chat.accentInk : scheme.onSurfaceVariant;
    final label = emoji == null
        ? S.of(context).t('a11y.addReaction')
        : S.of(context).t('a11y.reactWith', {'emoji': emoji});
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: ShapeDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        shape: StadiumBorder(
          side: active
              ? BorderSide(color: scheme.primary, width: 1.2)
              : BorderSide(
                  color: scheme.outlineVariant,
                  width: AppBorder.hairline,
                ),
        ),
      ),
      child: emoji == null
          ? Icon(Icons.add_reaction_outlined, size: 14, color: fg)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
    );
    return Semantics(
      button: true,
      label: label,
      value: widget.count == null ? null : '${widget.count}',
      selected: active,
      // 시각 캡슐은 작게 두고 탭 영역은 최소 48dp 확보. 개수가 커져 캡슐이 넓어지면 같이 넓어짐
      child: PressScale(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: InkWell(
            onTap: _handleTap,
            customBorder: const StadiumBorder(),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: AnimatedBuilder(
                animation: _pop,
                builder: (context, child) =>
                    Transform.scale(scale: 1 + _pop.value, child: child),
                child: pill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
