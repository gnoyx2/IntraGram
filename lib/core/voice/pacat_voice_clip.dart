import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'linux_audio.dart';
import 'voice_clip.dart';
import 'voice_wav.dart';

// Linux: PulseAudio 또는 PipeWire에 PCM을 stdin으로 넘김 (파일·캐시 없음).
// 일시정지는 프로세스를 끝내고 들은 위치를 기억했다가 거기서 새로 띄움
class PacatVoiceClip extends PolledVoiceClip {
  @visibleForTesting
  PacatVoiceClip(this._wav, {ProcessStarter? start})
    : _start = start ?? Process.start,
      super(_wav.duration);

  static Future<VoiceClip> load(PcmWav wav) async => PacatVoiceClip(wav);

  final PcmWav _wav;
  final ProcessStarter _start;
  final Stopwatch _clock = Stopwatch();
  Process? _process;
  var _offset = 0;
  var _exited = false;
  // 이 음성에서 PulseAudio 도구가 비정상 종료하면(서버 없음 등) 그 뒤로는 PipeWire만 씀
  var _pulseFailed = false;
  // 멈춤·해제·새 시작마다 올림: 그 사이 늦게 뜬 재시작 프로세스는 바로 끔
  var _generation = 0;

  @override
  Future<void> startOutput({required bool rewind}) async {
    if (rewind) _offset = 0;
    await _open(++_generation);
  }

  Future<void> _open(int generation) async {
    final audio = await startLinuxAudio(
      recording: false,
      sampleRate: _wav.sampleRate,
      channels: _wav.channels,
      start: _start,
      pulse: !_pulseFailed,
    );
    final process = audio.process;
    drainAudioDiagnostics(process);
    unawaited(process.stdout.drain<void>());
    if (generation != _generation) {
      process.kill();
      return;
    }
    _process = process;
    _exited = false;
    unawaited(process.exitCode.then((code) => _ended(audio, code)));
    process.stdin.add(Uint8List.sublistView(_wav.pcm, _offset));
    unawaited(process.stdin.close().then<void>((_) {}, onError: (_) {}));
    _clock
      ..reset()
      ..start();
  }

  void _ended(LinuxAudio audio, int code) {
    if (!identical(_process, audio.process)) return; // 우리가 멈춘 프로세스
    if (code == 0) {
      _exited = true;
      return;
    }
    // 재생 도중 비정상 종료됨: 들은 위치까지 기록하고, PulseAudio였으면 그 자리부터 PipeWire로 한 번만 다시 띄움
    _offset = _playedBytes();
    _clock
      ..stop()
      ..reset();
    _process = null;
    final failure = ProcessException(
      audio.executable,
      const [],
      'playback ended with exit code $code',
      code,
    );
    if (!audio.pulse || _pulseFailed) {
      markFailed(_position(), failure);
      return;
    }
    _pulseFailed = true;
    unawaited(
      _open(++_generation).then<void>(
        (_) {},
        onError: (Object error) => markFailed(_position(), error),
      ),
    );
  }

  @override
  Future<void> pauseOutput() async {
    _generation++;
    _clock.stop();
    _offset = _playedBytes();
    _clock.reset();
    _stopProcess();
  }

  @override
  Future<Duration> outputPosition() async => _position();

  @override
  Future<bool> outputFinished() async => _exited;

  @override
  Future<void> releaseOutput() async {
    _generation++;
    _clock.stop();
    _stopProcess();
  }

  Duration _position() => Duration(
    microseconds:
        _playedBytes() * Duration.microsecondsPerSecond ~/ _wav.byteRate,
  );

  // 시작 위치 + 흐른 시간만큼, 샘플 경계에 맞춤
  int _playedBytes() {
    final block = _wav.channels * 2;
    final elapsed =
        _clock.elapsedMicroseconds *
        _wav.byteRate ~/
        Duration.microsecondsPerSecond;
    final played = _offset + elapsed - elapsed % block;
    final total = _wav.samples.lengthInBytes;
    return played > total ? total : played;
  }

  void _stopProcess() {
    final process = _process;
    _process = null;
    process?.kill();
  }
}
