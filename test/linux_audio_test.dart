import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/voice/linux_audio.dart';
import 'package:intragram/core/voice/pacat_voice_clip.dart';
import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/core/voice/voice_wav.dart';
import 'package:intragram/features/chat/voice_recorder.dart';

import 'support/audio_process.dart';

// 실행한 도구 이름을 순서대로 적고(--help 조회 제외) 도구별 가짜 프로세스를 돌려줌. missing은 ENOENT
class _Tools {
  _Tools({this.missing = const {}, this.hold});
  final Set<String> missing;
  // 이 도구는 release가 끝날 때까지 뜨는 중으로 머묾
  final String? hold;
  final release = Completer<void>();
  final calls = <String>[];
  final started = <String, List<AudioProcess>>{};

  AudioProcess last(String executable) => started[executable]!.last;

  Future<Process> call(String executable, List<String> arguments) async {
    if (arguments.contains('--help')) return AudioProcess.help();
    calls.add(executable);
    if (missing.contains(executable)) {
      throw ProcessException(executable, arguments, 'missing', 2);
    }
    if (executable == hold) await release.future;
    final process = AudioProcess();
    (started[executable] ??= []).add(process);
    return process;
  }
}

void main() {
  for (final recording in [false, true]) {
    final pulse = recording ? 'parecord' : 'pacat';
    final pipewire = recording ? 'pw-record' : 'pw-play';
    for (final fallback in [pipewire, 'pw-cat']) {
      test('$pulse falls back to $fallback using only raw PCM pipes', () async {
        final calls = <String>[];
        final process = AudioProcess();
        final result = await startLinuxAudio(
          recording: recording,
          sampleRate: 16000,
          channels: 1,
          start: (executable, arguments) async {
            if (executable == fallback && arguments.contains('--help')) {
              return AudioProcess.help();
            }
            calls.add(executable);
            if (executable != fallback) {
              throw ProcessException(executable, arguments, 'missing', 2);
            }
            expect(
              arguments,
              containsAll([
                '--format=s16',
                '--rate=16000',
                '--channels=1',
                '-',
              ]),
            );
            expect(arguments, contains('--raw'));
            return process;
          },
        );
        expect(result.process, same(process));
        expect(result.executable, fallback);
        expect(result.pulse, isFalse);
        expect(calls, [pulse, pipewire, if (fallback == 'pw-cat') 'pw-cat']);
        process.kill();
      });
    }
  }

  test('older PipeWire tools use their implicit raw stdin mode', () async {
    final process = AudioProcess();
    await startLinuxAudio(
      recording: false,
      sampleRate: 16000,
      channels: 1,
      start: (executable, arguments) async {
        if (executable == 'pacat') {
          throw ProcessException(executable, arguments, 'missing', 2);
        }
        if (arguments.contains('--help')) {
          return AudioProcess.help(rawSupported: false);
        }
        expect(arguments, isNot(contains('--raw')));
        expect(arguments.last, '-');
        return process;
      },
    );
    process.kill();
  });

  test('permission failures do not open another capture process', () async {
    final calls = <String>[];
    await expectLater(
      startLinuxAudio(
        recording: true,
        sampleRate: 16000,
        channels: 1,
        start: (executable, arguments) async {
          calls.add(executable);
          throw ProcessException(executable, arguments, 'denied', 13);
        },
      ),
      throwsA(isA<ProcessException>()),
    );
    expect(calls, ['parecord']);
  });

  test('pulse: false goes straight to PipeWire', () async {
    final tools = _Tools();
    final audio = await startLinuxAudio(
      recording: true,
      sampleRate: 16000,
      channels: 1,
      start: tools.call,
      pulse: false,
    );
    expect(tools.calls, ['pw-record']);
    expect(audio.pulse, isFalse);
  });

  group('PipeWire playback', () {
    final pcm = Uint8List.fromList(List.generate(32000, (i) => i % 251));
    PcmWav wav() => parsePcm16Wav(encodePcm16WavForTesting(pcm))!;

    test('missing pacat plays exactly the PCM bytes through pw-play', () async {
      final tools = _Tools(missing: {'pacat'});
      final clip = PacatVoiceClip(wav(), start: tools.call);
      await clip.play();
      await pumpEventQueue();
      expect(tools.last('pw-play').inputBytes, pcm);
      await clip.dispose();
      expect(tools.last('pw-play').killed, isTrue);
    });

    test(
      'pacat that cannot reach a server hands the rest to pw-play once',
      () async {
        final tools = _Tools();
        final clip = PacatVoiceClip(wav(), start: tools.call);
        await clip.play();
        tools.last('pacat').exitWith(1); // "Connection failure" → quit(1)
        await pumpEventQueue();
        expect(tools.calls, ['pacat', 'pw-play']);
        final rest = tools.last('pw-play').inputBytes;
        // 실패까지 흐른 수 ms만 건너뜀: 처음부터 다시 틀지 않음(중복 재생 없음)
        expect(rest.length, greaterThan(pcm.length - 640));
        expect(rest, pcm.sublist(pcm.length - rest.length));
        tools.last('pw-play').exitWith(0);
        expect(
          (await clip.progress.firstWhere((p) => p.completed)).completed,
          isTrue,
        );
        await clip.play();
        expect(tools.calls.last, 'pw-play', reason: 'Pulse is not tried again');
        await clip.dispose();
      },
    );

    test('both outputs failing is an error, not a finished note', () async {
      final tools = _Tools();
      final clip = PacatVoiceClip(wav(), start: tools.call);
      final events = <Object>[];
      final sub = clip.progress.listen(events.add, onError: events.add);
      await clip.play();
      tools.last('pacat').exitWith(1);
      await pumpEventQueue();
      tools.last('pw-play').exitWith(1);
      await pumpEventQueue();
      expect(tools.calls, ['pacat', 'pw-play'], reason: 'no retry loop');
      expect(events.last, isA<ProcessException>());
      final states = events.whereType<VoiceProgress>();
      expect(states.last.playing, isFalse);
      expect(states.any((p) => p.completed), isFalse);
      await sub.cancel();
      await clip.dispose();
    });

    test('a pause while pw-play starts leaves no stray process', () async {
      final tools = _Tools(hold: 'pw-play');
      final clip = PacatVoiceClip(wav(), start: tools.call);
      await clip.play();
      tools.last('pacat').exitWith(1);
      await pumpEventQueue();
      expect(tools.calls, ['pacat', 'pw-play']);
      await clip.pause();
      tools.release.complete();
      await pumpEventQueue();
      expect(tools.last('pw-play').killed, isTrue);
      expect(tools.last('pw-play').inputBytes, isEmpty);
      await clip.dispose();
    });

    test('a normal end or a user stop never starts PipeWire', () async {
      final tools = _Tools();
      final clip = PacatVoiceClip(wav(), start: tools.call);
      await clip.play();
      tools.last('pacat').exitWith(0);
      await clip.progress.firstWhere((p) => p.completed);
      await clip.play();
      await clip.pause();
      await pumpEventQueue();
      expect(tools.calls, ['pacat', 'pacat']);
      await clip.dispose();
    });

    test('a paused position counts the played time once', () async {
      final clip = PacatVoiceClip(wav(), start: _Tools().call);
      final wall = Stopwatch()..start();
      await clip.play();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final paused = clip.progress.first;
      await clip.pause();
      expect((await paused).position, lessThanOrEqualTo(wall.elapsed));
      await clip.dispose();
    });
  });
}
