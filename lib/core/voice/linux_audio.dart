import 'dart:convert';
import 'dart:io';

typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

// 띄운 오디오 도구. pulse는 PulseAudio 도구(pacat·parecord): 서버가 없으면 소리를 내기 전에 1로 끝남
typedef LinuxAudio = ({Process process, String executable, bool pulse});

// PCM은 파이프로만 다님. PulseAudio 도구가 없거나 pulse가 false면 PipeWire 도구를 띄움.
// 도구는 있는데 서버에 못 붙어 바로 끝나는 경우는 호출부가 pulse: false로 한 번만 다시 띄움
Future<LinuxAudio> startLinuxAudio({
  required bool recording,
  required int sampleRate,
  required int channels,
  ProcessStarter? start,
  bool pulse = true,
}) async {
  final spawn = start ?? Process.start;
  if (pulse) {
    final executable = recording ? 'parecord' : 'pacat';
    try {
      final process = await spawn(executable, [
        if (!recording) '--playback',
        '--raw',
        '--format=s16le',
        '--rate=$sampleRate',
        '--channels=$channels',
        '--latency-msec=100',
        '--client-name=Intragram',
      ]);
      return (process: process, executable: executable, pulse: true);
    } on ProcessException catch (error) {
      if (error.errorCode != 2) rethrow;
    }
  }
  final pipewire = recording ? 'pw-record' : 'pw-play';
  Future<LinuxAudio> pipe(String executable) async {
    final help = await spawn(executable, ['--help']);
    drainAudioDiagnostics(help);
    final usage = await utf8.decoder.bind(help.stdout).join();
    await help.exitCode;
    final process = await spawn(executable, [
      if (executable == 'pw-cat') recording ? '--record' : '--playback',
      // PipeWire 1.0·1.2는 "-"를 raw PCM으로 읽고, 1.4부터는 --raw가 있어야 함
      if (usage.contains('--raw')) '--raw',
      '--format=s16',
      '--rate=$sampleRate',
      '--channels=$channels',
      '--latency=100ms',
      '-',
    ]);
    return (process: process, executable: executable, pulse: false);
  }

  try {
    return await pipe(pipewire);
  } on ProcessException catch (error) {
    if (error.errorCode != 2) rethrow;
    return pipe('pw-cat');
  }
}

// 재생 중에도 PipeWire의 진단 출력(stderr)을 모두 소비해야 함
void drainAudioDiagnostics(Process process) {
  process.stderr.drain<void>().ignore();
}
