import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'channel_voice_clip.dart';
import 'pacat_voice_clip.dart';
import 'voice_wav.dart';
import 'wave_out_voice_clip.dart';

@immutable
class VoiceProgress {
  const VoiceProgress({
    required this.playing,
    required this.completed,
    required this.position,
  });

  final bool playing;
  final bool completed;
  final Duration position;
}

// 메모리의 WAV를 플랫폼 재생기에 바로 넘김. 디스크·캐시·로컬 HTTP 프록시를 안 거쳐서 들은 음성이 임시 폴더에 평문으로 안 남음
abstract interface class VoiceClip {
  Duration get duration;
  Stream<VoiceProgress> get progress;

  // 끝까지 들었으면 처음부터 다시 재생함
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

typedef VoiceClipLoader = Future<VoiceClip> Function(PcmWav wav);

// 테스트용 재생기 교체 자리 (프로덕션은 null)
@visibleForTesting
VoiceClipLoader? debugVoiceClipLoader;

// 16비트 PCM WAV가 아니면 FormatException을 던짐 (호출부가 '재생할 수 없음'을 띄움)
Future<VoiceClip> loadVoiceClip(Uint8List bytes) async {
  final wav = parsePcm16Wav(bytes);
  if (wav == null) throw const FormatException('not a 16-bit PCM voice note');
  final loader =
      debugVoiceClipLoader ??
      (Platform.isWindows
          ? WaveOutVoiceClip.load
          : Platform.isLinux
          ? PacatVoiceClip.load
          : ChannelVoiceClip.load);
  return loader(wav);
}

// 플랫폼마다 출력만 다르고 위치 폴링·상태 방송·끝 처리는 여기서 같이 함
abstract class PolledVoiceClip implements VoiceClip {
  PolledVoiceClip(this.duration);

  @override
  final Duration duration;

  static const Duration _tick = Duration(milliseconds: 100);

  final StreamController<VoiceProgress> _progress =
      StreamController<VoiceProgress>.broadcast();
  Timer? _ticker;
  bool _playing = false;
  bool _completed = false;
  bool _disposed = false;
  // 출력 여는 중(pacat 프로세스 뜨는 중 등). 그 사이 play는 무시하고 dispose는 끝나길 기다렸다 닫음
  Future<void>? _starting;

  @override
  Stream<VoiceProgress> get progress => _progress.stream;

  @protected
  Future<void> startOutput({required bool rewind});
  @protected
  Future<void> pauseOutput();
  @protected
  Future<Duration> outputPosition();
  // 폴링으로 종료를 감지하는 플랫폼만 true를 반환함 (이벤트 방식은 markCompleted를 부름)
  @protected
  Future<bool> outputFinished();
  @protected
  Future<void> releaseOutput();

  @override
  Future<void> play() async {
    if (_disposed || _playing || _starting != null) return;
    final rewind = _completed;
    final start = _starting = startOutput(rewind: rewind);
    try {
      await start;
    } finally {
      _starting = null;
    }
    if (_disposed) return;
    _completed = false;
    _playing = true;
    _emit(rewind ? Duration.zero : await outputPosition());
    _ticker ??= Timer.periodic(_tick, (_) => unawaited(_poll()));
  }

  @override
  Future<void> pause() async {
    if (_disposed || !_playing) return;
    _stopTicker();
    _playing = false;
    await pauseOutput();
    if (!_disposed) _emit(await outputPosition());
  }

  @protected
  void markCompleted() {
    if (_disposed || _completed) return;
    _stopTicker();
    _playing = false;
    _completed = true;
    _emit(duration);
  }

  // 출력이 도중에 비정상 종료됨: 완료로 치지 않고 그 자리에서 멈춘 뒤 구독자에 오류를 알림
  @protected
  void markFailed(Duration position, Object error) {
    if (_disposed || !_playing) return;
    _stopTicker();
    _playing = false;
    _emit(position);
    if (!_progress.isClosed) _progress.addError(error);
  }

  Future<void> _poll() async {
    if (!_playing || _disposed) return;
    if (await outputFinished()) {
      markCompleted();
      return;
    }
    final position = await outputPosition();
    if (_playing && !_disposed) _emit(position);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopTicker();
    _playing = false;
    try {
      await _starting;
    } on Object {
      // 시작이 실패했어도 닫기는 함 (실패는 play 쪽이 알림)
    }
    await releaseOutput();
    await _progress.close();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emit(Duration position) {
    if (_progress.isClosed) return;
    _progress.add(
      VoiceProgress(
        playing: _playing,
        completed: _completed,
        position: position > duration ? duration : position,
      ),
    );
  }
}
