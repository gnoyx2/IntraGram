part of '../voice_recorder.dart';

extension _VoiceRecorderBanner on _VoiceRecorderButtonState {
  // _bannerLink로 버튼에 계속 따라붙는 Follower 방식: 좌표를 얼리는 대신 키보드 열림/화면 회전으로
  // 버튼이 움직여도 컴포지팅 레이어에서 매 프레임 같이 움직임
  void _showBanner() {
    final overlay = Overlay.of(context);

    _banner = OverlayEntry(
      builder: (overlayContext) {
        final scheme = Theme.of(overlayContext).colorScheme;
        final s = S.of(overlayContext);
        final media = MediaQuery.of(overlayContext);
        final minX = media.padding.left + AppSpacing.md;
        final maxX = media.size.width - media.padding.right - AppSpacing.md;
        final bubbleWidth = math.min(
          240 + (media.textScaler.scale(15) - 15) * 4,
          math.max(0.0, maxX - minX),
        );
        final target = context.findRenderObject();
        final root = overlay.context.findRenderObject();
        final centerX = target is RenderBox && root is RenderBox
            ? target
                  .localToGlobal(
                    Offset(target.size.width / 2, 0),
                    ancestor: root,
                  )
                  .dx
            : media.size.width / 2;
        final left = (centerX - bubbleWidth / 2)
            .clamp(minX, maxX - bubbleWidth)
            .toDouble();
        final offsetX = left + bubbleWidth / 2 - centerX;

        // 취소 임계값에서 뚝 끊기지 않고 위로 미는 거리에 비례해 배경이 붉어짐 (드래그 중에도 남은 거리가 느껴짐)
        final progress = _cancelProgress;
        final background = scheme.brightness == Brightness.dark
            ? scheme.surfaceContainerHighest
            : scheme.inverseSurface;
        final foreground = scheme.brightness == Brightness.dark
            ? scheme.onSurface
            : scheme.onInverseSurface;
        final tint = Color.lerp(background, AppPalette.burnLight, progress)!;
        final level = ((_amplitude + 45) / 45).clamp(0.0, 1.0).toDouble();

        // Align은 Follower 바깥에: 안에 두면 Overlay의 tight 제약(화면 크기)이 그대로 넘어가 배너가 화면 위로 사라짐
        // (바깥 Align이 제약을 풀어 말풍선 크기로 줄임)
        return Align(
          child: CompositedTransformFollower(
            link: _bannerLink,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            // 버튼 위로 고정 간격만 띄움. Scaffold가 이미 키보드만큼 anchor를 밀어 올려서
            // viewInsets.bottom을 또 빼면 이중 반영이 됨
            offset: Offset(offsetX, -AppSpacing.xxl),
            showWhenUnlinked: false,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: bubbleWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: motionDuration(
                        context,
                        const Duration(milliseconds: 120),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _cancelled
                                ? Icons.delete
                                : Icons.fiber_manual_record,
                            color: _cancelled
                                ? foreground
                                : AppPalette.burnDark,
                            size: 16,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _format(_elapsed),
                            style: TextStyle(color: foreground),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _WaveformBars(
                              level: level,
                              elapsed: _elapsed,
                              color: foreground,
                            ),
                          ),
                          if (_tapLocked && !_cancelled) ...[
                            const SizedBox(width: AppSpacing.xs),
                            _BannerButton(
                              icon: Icons.close,
                              tooltip: s.t('voice.tapToCancel'),
                              onTap: () => unawaited(_stop(send: false)),
                            ),
                            _BannerButton(
                              icon: Icons.check_circle,
                              tooltip: s.t('input.send'),
                              onTap: () => unawaited(_stop(send: true)),
                            ),
                          ] else if (!_cancelled)
                            Icon(
                              Icons.keyboard_double_arrow_up,
                              size: 16,
                              color: Color.lerp(
                                foreground.withValues(alpha: 0.7),
                                AppPalette.burnDark,
                                progress,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 말풍선 꼬리. margin은 음수가 안 돼서 겹치는 만큼은 Transform으로 옮김
                    Transform.translate(
                      offset: const Offset(0, -5),
                      child: Transform.rotate(
                        angle: math.pi / 4,
                        child: Container(width: 10, height: 10, color: tint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_banner!);
  }
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    // 시각 아이콘은 작게 두고 탭 영역은 48dp 확보 (reaction_chips.dart와 같은 패턴)
    child: SizedBox(
      width: 48,
      height: 48,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Center(child: Icon(icon, color: Colors.white, size: 18)),
      ),
    ),
  );
}
