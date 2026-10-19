part of '../transfer_tile.dart';

// 재생기는 첫 재생 탭에서야 만듦 (스레드에 음성 버블이 여러 개여도 각자 재생기를 안 쥠)
// 재생기는 메모리의 바이트를 네이티브 출력에 바로 넘겨서 재생해도 디스크·캐시에 남지 않음
class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({
    required this.bytes,
    required this.color,
    this.encrypted = false,
  });
  final Uint8List bytes;
  final Color color;
  final bool encrypted;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  VoiceClip? _clip;
  StreamSubscription<VoiceProgress>? _progressSub;
  VoiceProgress? _last;
  bool _loading = false;
  late final List<double> _waveform = _waveformFor(widget.bytes);
  late final Duration _length = _wavDuration(widget.bytes);

  // 중복 탭이 재생기를 두 개 만들어 하나가 새는 걸 막음
  // 성공/실패 한 번이면 지움 (재시도는 새로 만듦)
  Future<VoiceClip?>? _initFuture;

  @override
  void dispose() {
    VoiceProducerRegistry.instance.unregister(_panicStop);
    unawaited(_progressSub?.cancel());
    unawaited(_clip?.dispose());
    super.dispose();
  }

  // 패닉용 강제 정지: widget.bytes가 소각되기 전에 재생기를 먼저 놓음
  // 화면이 사라지는 중일 수 있어 context/setState 안 씀
  Future<void> _panicStop() async {
    final clip = _clip;
    _clip = null;
    await _progressSub?.cancel();
    _progressSub = null;
    await clip?.dispose();
  }

  // 기본은 zero-disk라 재생만 되고 앱을 끄면 사라짐. 사용자가
  // 눌러야만 디스크에 씀 (받은 파일 수락과 같은 목적지 선택 로직 재사용)
  // 폴더 선택 중 화면이 닫히거나 세션이 소각될 수 있어서 선택 뒤/쓰기
  // 직전에 mounted를 재확인 (소각돼 지워진 바이트를 저장하지 않으려고)
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final name = 'voice-${DateTime.now().millisecondsSinceEpoch}.wav';
    final String? dir;
    try {
      dir = await IncomingPathResolver.defaultChooseDirectory(name);
    } on PickerUnavailableException {
      if (mounted) showPickerUnavailable(context);
      return;
    }
    if (dir == null || !mounted) return;
    try {
      final path = await IncomingPathResolver.saveBytes(
        directory: dir,
        name: name,
        bytes: widget.bytes,
        isStillWanted: () => mounted,
      );
      if (path == null) return; // 그 사이 화면이 닫힘
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('transfer.savedTo', {'path': path}))),
      );
    } on Object {
      // 타일이 사라졌어도 채팅 화면(messenger)이 살아 있으면 실패를 보여줌
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('transfer.saveFailed'))),
      );
    }
  }

  // 실패(형식이 아님, 출력 장치 없음, Linux pacat 없음 등)면 null (호출부가 "재생할 수 없음"을 보여 줌)
  Future<VoiceClip?> _initClip() async {
    try {
      return await loadVoiceClip(widget.bytes);
    } on Object {
      return null;
    }
  }

  Future<void> _toggle() async {
    // 다음 프레임에 버튼이 비활성화되기 전 연속 탭도 한 번만 처리함
    if (_loading) return;
    AppHaptics.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    var clip = _clip;
    if (clip == null) {
      final existing = _initFuture;
      final Future<VoiceClip?> initFuture;
      if (existing != null) {
        initFuture = existing;
      } else {
        if (mounted) setState(() => _loading = true);
        initFuture = _initClip();
        _initFuture = initFuture;
      }
      clip = await initFuture;
      if (identical(_initFuture, initFuture)) _initFuture = null;
      if (clip == null) {
        if (mounted) {
          setState(() => _loading = false);
          messenger.showSnackBar(
            SnackBar(content: Text(s.t('transfer.cannotPlay'))),
          );
        }
        return;
      }
      if (!mounted) {
        // 로드를 기다리는 동안 화면이 사라짐: 아무도 안 쓸 재생기를 필드에 안 남기고 바로 정리
        await clip.dispose();
        return;
      }
      _clip = clip;
      _progressSub = clip.progress.listen((p) => _last = p);
      VoiceProducerRegistry.instance.register(_panicStop);
      setState(() => _loading = false);
    }
    try {
      if (_last?.playing ?? false) {
        await clip.pause();
      } else {
        await clip.play();
      }
    } on Object {
      // 출력 장치가 사라졌거나 재생기가 거부함: 조용히 멈춘 척하지 않고 알림
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('transfer.cannotPlay'))),
      );
    }
  }

  // 재생 버튼 · 파형과 길이 · 저장 버튼. 카드 폭은 파일 카드와 같은 상한을 씀
  @override
  Widget build(BuildContext context) {
    final clip = _clip;
    final accent = Theme.of(context).colorScheme.primary;
    final muted = widget.color.withValues(alpha: AppOpacity.secondaryText);
    final clockStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: muted,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kCardWidth - 24),
      child: StreamBuilder<VoiceProgress>(
        stream: clip?.progress,
        initialData: _last,
        builder: (context, snap) {
          final progress = snap.data;
          final playing = progress?.playing ?? false;
          final position = progress?.position ?? Duration.zero;
          final total = clip?.duration ?? _length;
          final value = total.inMilliseconds == 0 || clip == null
              ? 0.0
              : (position.inMilliseconds / total.inMilliseconds)
                    .clamp(0.0, 1.0)
                    .toDouble();
          return Row(
            children: [
              _PlayButton(
                playing: playing,
                loading: _loading,
                onPressed: _toggle,
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 24,
                      width: double.infinity,
                      child: _WaveformBars(
                        bars: _waveform,
                        progress: value,
                        played: accent,
                        idle: widget.color.withValues(alpha: 0.28),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Text(
                          _formatClock(clip == null ? _length : position),
                          style: clockStyle,
                        ),
                        if (widget.encrypted) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Semantics(
                            label: S.of(context).t('a11y.encrypted'),
                            child: Icon(
                              Icons.lock_rounded,
                              size: MediaQuery.textScalerOf(context).scale(11),
                              color: muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                color: muted,
                tooltip: S.of(context).t('transfer.saveToDevice'),
                onPressed: _save,
                icon: const Icon(Icons.download_outlined, size: 20),
              ),
            ],
          );
        },
      ),
    );
  }
}
