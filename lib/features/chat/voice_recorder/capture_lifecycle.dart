part of '../voice_recorder.dart';

// 녹음 시작/종료 전이
extension _VoiceRecorderCapture on _VoiceRecorderButtonState {
  Future<void> _start({required bool tapLocked}) async {
    if (!widget.enabled || _busy || _capture != null) return;
    _busy = true;
    _pendingSend = null;
    final generation = ++_captureGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final capture = widget.createCapture();
    try {
      if (!await capture.hasPermission()) {
        if (mounted) {
          // iOS·macOS는 한 번 거부하면 다시 묻지 않아서 설정 화면으로 보내는 게 유일한 복구 경로
          messenger.showSnackBar(
            SnackBar(
              content: Text(s.t('voice.micPermission')),
              action: canOpenSettings(SettingsPane.microphone)
                  ? SnackBarAction(
                      label: s.t('settings.open'),
                      onPressed: () => openSettings(SettingsPane.microphone),
                    )
                  : null,
            ),
          );
        }
        await capture.dispose();
        return;
      }
      if (!mounted || !widget.enabled || generation != _captureGeneration) {
        // 권한 대기 중 화면이 닫히거나 비활성화됨: 마이크를 열지 않고 여기서 끝냄
        await capture.dispose();
        return;
      }
      await capture.start();
      if (!mounted || generation != _captureGeneration) {
        await capture.cancel();
        await capture.dispose();
        return;
      }
      final stopwatch = Stopwatch()..start();
      _applyStarted(
        capture: capture,
        stopwatch: stopwatch,
        tapLocked: tapLocked,
      );
      if (_pendingSend != false) AppHaptics.lightImpact();
      _amplitudeSub = capture.amplitudeStream.listen(
        (level) {
          _amplitude = level;
          _banner?.markNeedsBuild();
        },
        // 녹음 도구가 도중에 끝남: 손을 뗄 때까지 기다리지 않고 바로 멈춰 '저장하지 못함'을 알림
        onError: (Object _) => unawaited(_stop(send: true)),
      );
      _showBanner();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final elapsed = stopwatch.elapsed;
        _updateElapsed(elapsed);
        _banner?.markNeedsBuild();
        if (elapsed.inSeconds >= kMaxVoiceNoteSeconds) {
          unawaited(_stop(send: true));
        }
      });
    } on Object {
      if (mounted) {
        // Linux에서 쓸 수 있는 PipeWire/PulseAudio 녹음 도구가 없으면 여기로 옴
        final key = defaultTargetPlatform == TargetPlatform.linux
            ? 'voice.couldNotStartLinux'
            : 'voice.couldNotStart';
        messenger.showSnackBar(SnackBar(content: Text(s.t(key))));
      }
      await capture.dispose();
    } finally {
      _busy = false;
      // 시작 중에 뗀 의사를 이제 실행함 (false는 한 번 오면 안 바뀜)
      final pending = _pendingSend;
      if (pending != null && _capture != null) {
        _pendingSend = null;
        unawaited(_stop(send: pending));
      }
    }
  }

  Future<void> _stop({required bool send}) async {
    final capture = _capture;
    if (capture == null) {
      // 시작 중(권한 대기 등)이면 뗀 순간의 의사를 기억했다가 시작이 끝나면 실행함
      // false는 한 번 오면 이후 true가 와도 안 덮음 (_pendingSend 참고)
      if (_busy && _pendingSend != false) _pendingSend = send;
      return;
    }
    if (_busy) return;
    _busy = true;
    final generation = _captureGeneration;
    _ticker?.cancel();
    _ticker = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _banner?.remove();
    _banner = null;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    final elapsed = _stopwatch?.elapsed ?? _elapsed;
    final deliver = send && !_cancelled;
    if (!deliver && !_cancelled) AppHaptics.mediumImpact();
    _applyStopped();

    Uint8List? bytes;
    try {
      if (deliver) {
        bytes = await capture.finish();
      } else {
        await capture.cancel();
      }
    } on Object {
      // 원본 예외는 화면에 안 보여주고 번역된 실패만 알림
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(s.t('voice.stopFailed'))),
        );
      }
    } finally {
      try {
        await capture.dispose();
      } on Object {
        // 리소스 해제 실패로 버튼이 계속 busy로 묶이면 안 됨
      }
      _busy = false;
    }

    if (!mounted || !widget.enabled || generation != _captureGeneration) {
      // 위젯이 사라졌거나 비활성화됐거나 새 녹음 세대가 시작됨: 낡은 결과라 전달하지 않고 바로 지움
      if (bytes != null) SecureBytes.wipe(bytes);
      return;
    }
    if (!deliver || bytes == null || bytes.isEmpty) return;
    if (bytes.length > kMaxVoiceNoteBytes) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(s.t('voice.tooLong'))));
      }
      return;
    }
    if (elapsed.inMilliseconds < 700) {
      // 실수로 톡 친 것. 아무 반응 없으면 씹힌 것처럼 보여서 한 줄 알림
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(s.t('voice.tooShort'))));
      }
      return;
    }
    AppHaptics.lightImpact();
    widget.onRecorded(bytes);
  }
}
