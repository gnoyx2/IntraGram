import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import 'package:intragram/core/app_settings.dart';
import 'package:intragram/core/haptics.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/secure_bytes.dart';
import 'package:intragram/core/voice_producer_registry.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/motion.dart';
import 'package:intragram/theme/tokens.dart';

part 'voice_recorder/voice_capture.dart';
part 'voice_recorder/wav.dart';
part 'voice_recorder/banner.dart';
part 'voice_recorder/waveform_bars.dart';
part 'voice_recorder/gestures.dart';
part 'voice_recorder/capture_lifecycle.dart';

// 바이트는 RAM으로만 넘어감 (디스크/보관소 안 거침)
class VoiceRecorderButton extends StatefulWidget {
  const VoiceRecorderButton({
    required this.enabled,
    required this.onRecorded,
    this.createCapture = RecordVoiceCapture.new,
    super.key,
  });

  final bool enabled;
  final ValueChanged<Uint8List> onRecorded;

  // 테스트용 녹음 백엔드 주입
  final VoiceCapture Function() createCapture;

  @override
  State<VoiceRecorderButton> createState() => _VoiceRecorderButtonState();
}

class _VoiceRecorderButtonState extends State<VoiceRecorderButton>
    with WidgetsBindingObserver {
  VoiceCapture? _capture;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  // 700ms 판정과 120초 상한의 유일한 시간 원천. _ticker는 표시 갱신용 1초 주기라 지연되면 둘이 같이 밀림
  Stopwatch? _stopwatch;
  bool _cancelled = false;

  // 0(안전) ~ 1(취소 확정). 위로 미는 거리에 비례해 배너 색/투명도를 연속 보간함
  double _cancelProgress = 0;
  bool _busy = false;

  // 시작(권한 요청 포함)이 끝나기 전에 손을 뗀 경우의 최종 의사 (null 없음, false 취소, true 전송)
  // 한 번 false면 이후 true가 와도 안 덮음 (권한 대기 중 취소가 전송으로 둔갑하던 버그 방지)
  bool? _pendingSend;

  // _start 호출마다 증가. await 뒤에 다시 확인해서 그사이 dispose/재시작된 낡은 결과가
  // 최신 상태를 덮지 않게 함
  int _captureGeneration = 0;

  OverlayEntry? _banner;

  // 배너를 버튼의 현재 위치에 계속 고정시키는 링크 (Follower 방식)
  final LayerLink _bannerLink = LayerLink();

  // 홀드가 아니라 짧은 탭으로 시작한 핸즈프리 녹음 모드 (아이콘이 X로 바뀌고 배너에 전송 체크 버튼이 뜸)
  bool _tapLocked = false;

  // 실시간 음량(dBFS, 대략 -45~0). 배너 파형 모션용이고 녹음 중이 아니면 무음
  double _amplitude = _silenceDb;
  StreamSubscription<double>? _amplitudeSub;
  static const _silenceDb = -45.0;

  // 홀드-투-녹음 판정을 쥔 포인터. 다른 손가락이나 마우스 우클릭이 판정을 가로채지 못하게 함
  // (GestureDetector.onLongPress*는 안 씀, build 주석 참고)
  int? _activePointer;
  Offset? _downPosition;
  Timer? _pressTimer;

  static const _holdDelay = Duration(milliseconds: 500);
  static const _moveSlopBeforeStart = 24.0;
  static const _cancelDistance = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드로 가면 녹음/권한 대기를 취소함 (안 보이는 동안 몰래 녹음 금지)
    if (state != AppLifecycleState.resumed && (_capture != null || _busy)) {
      unawaited(_stop(send: false));
    }
  }

  @override
  void didUpdateWidget(VoiceRecorderButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled && (_capture != null || _busy)) {
      unawaited(_stop(send: false));
    }
  }

  @override
  void dispose() {
    _captureGeneration++; // 늦게 끝나는 finish가 dispose 뒤 새 나가지 않게 함
    WidgetsBinding.instance.removeObserver(this);
    VoiceProducerRegistry.instance.unregister(_panicStop);
    _ticker?.cancel();
    _pressTimer?.cancel();
    _amplitudeSub?.cancel();
    _banner?.remove();
    _capture?.dispose();
    super.dispose();
  }

  // 패닉이 진행 중인 녹음을 백그라운드 전환과 같은 방식(send: false)으로 강제 중단하고 버림
  // _stop이 context/mounted를 써서 mounted일 때만 등록됨
  Future<void> _panicStop() => _stop(send: false);

  void _setCancelProgress(double progress, bool cancelled) {
    setState(() {
      _cancelProgress = progress;
      _cancelled = cancelled;
    });
  }

  // extension은 protected setState를 직접 못 불러서(State 서브클래스 멤버가 아님)
  // 상태 대입은 State 본체에 두고 판단 로직만 extension에 둠
  void _applyStarted({
    required VoiceCapture capture,
    required Stopwatch stopwatch,
    required bool tapLocked,
  }) {
    setState(() {
      _capture = capture;
      _stopwatch = stopwatch;
      _elapsed = Duration.zero;
      _cancelled = false;
      _cancelProgress = 0;
      _tapLocked = tapLocked;
      _amplitude = _silenceDb;
    });
    VoiceProducerRegistry.instance.register(_panicStop);
  }

  void _updateElapsed(Duration elapsed) {
    setState(() => _elapsed = elapsed);
  }

  void _applyStopped() {
    VoiceProducerRegistry.instance.unregister(_panicStop);
    setState(() {
      _capture = null;
      _stopwatch = null;
      _tapLocked = false;
    });
  }

  // 접근성 활성화(스크린 리더 더블탭, Space/Enter) 한 번으로 시작/종료를 오감: 대기 중이면
  // 핸즈프리 녹음 시작, 녹음 중이면 전송으로 끝냄. 취소는 배너의 별도 취소 버튼으로 가능
  void _onActivate() {
    if (!widget.enabled) return;
    if (_capture != null) {
      unawaited(_stop(send: true));
    } else if (!_busy) {
      unawaited(_start(tapLocked: true));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _onActivate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final recording = _capture != null;
    final showCancelIcon = recording && _tapLocked;
    final s = S.of(context);
    final label = !recording
        ? s.t('voice.holdToRecord')
        : s.t('voice.a11yRecording');
    return CompositedTransformTarget(
      link: _bannerLink,
      child: Focus(
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          // Tooltip/IconButton.tooltip은 자체 롱프레스 핸들러가
          // 홀드-투-녹음 제스처를 먹어서 안 씀 접근성 라벨은 Semantics로
          child: Semantics(
            button: true,
            enabled: widget.enabled,
            label: label,
            onTap: widget.enabled ? _onActivate : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                showCancelIcon
                    ? Icons.close
                    : recording
                    ? Icons.mic
                    : Icons.mic_none,
                color: recording
                    ? Theme.of(context).colorScheme.error
                    : widget.enabled
                    ? IconTheme.of(context).color
                    : Theme.of(context).disabledColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
