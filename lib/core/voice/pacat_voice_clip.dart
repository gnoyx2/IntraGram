import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'voice_clip.dart';
import 'voice_wav.dart';

typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

// Linux: PCM을 pacat(pulseaudio-utils, 녹음이 쓰는 parecord와 같은 패키지)의 stdin 파이프로 흘려보냄
// 파일·캐시를 안 거침. 일시정지는 프로세스를 끝내고 들은 만큼의 위치를 기억했다가 거기서 새로 시작함
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

  @override
  Future<void> startOutput({required bool rewind}) async {
    if (rewind) _offset = 0;
    final process = await _start('pacat', [
      '--playback',
      '--raw',
      '--format=s16le',
      '--rate=${_wav.sampleRate}',
      '--channels=${_wav.channels}',
      '--latency-msec=100',
      '--client-name=IntraGram',
    ]);
    _process = process;
    _exited = false;
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) _exited = true;
      }),
    );
    process.stdin.add(Uint8List.sublistView(_wav.pcm, _offset));
    unawaited(process.stdin.close().then<void>((_) {}, onError: (_) {}));
    _clock
      ..reset()
      ..start();
  }

  @override
  Future<void> pauseOutput() async {
    _clock.stop();
    _offset = _playedBytes();
    _stopProcess();
  }

  @override
  Future<Duration> outputPosition() async => Duration(
    microseconds:
        _playedBytes() * Duration.microsecondsPerSecond ~/ _wav.byteRate,
  );

  @override
  Future<bool> outputFinished() async => _exited;

  @override
  Future<void> releaseOutput() async {
    _clock.stop();
    _stopProcess();
  }

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
