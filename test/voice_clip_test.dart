import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/voice/channel_voice_clip.dart';
import 'package:intragram/core/voice/pacat_voice_clip.dart';
import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/core/voice/voice_wav.dart';
import 'package:intragram/features/chat/voice_recorder.dart';

// 음성 재생기는 바이트를 메모리로만 넘김: 네이티브 채널엔 검사를 통과한 표준 WAV를, Linux pacat엔
// PCM을 stdin 파이프로 전달하며 끝·일시정지·다시 듣기 상태가 위젯 쪽으로 흘러감
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pcm = Uint8List.fromList(List<int>.generate(32000, (i) => i % 251));
  final wav = parsePcm16Wav(encodePcm16WavForTesting(pcm))!;

  group('native channel player', () {
    const channel = MethodChannel('intragram/voice');
    final calls = <MethodCall>[];
    Uint8List? loaded;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final args = call.arguments as Map<Object?, Object?>;
            if (call.method == 'load') {
              loaded = Uint8List.fromList(args['bytes']! as Uint8List);
              return 1000;
            }
            return call.method == 'position' ? 250 : null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('hands over a canonical WAV and reports progress', () async {
      final clip = await ChannelVoiceClip.load(wav);
      expect(loaded!.sublist(0, 4), 'RIFF'.codeUnits);
      expect(parsePcm16Wav(loaded!)!.pcm, pcm);
      expect(clip.duration, const Duration(seconds: 1));

      final events = <VoiceProgress>[];
      final sub = clip.progress.listen(events.add);
      await clip.play();
      await pumpEventQueue();
      expect(events.last.playing, isTrue);
      await clip.pause();
      await pumpEventQueue();
      expect(events.last.playing, isFalse);
      expect(events.last.position, const Duration(milliseconds: 250));

      // 네이티브가 끝을 알림 → 다음 재생은 처음부터
      final id = (calls.first.arguments as Map)['id'];
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'intragram/voice',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('completed', id),
            ),
            (_) {},
          );
      await clip.play();
      final play = calls.lastWhere((c) => c.method == 'play');
      expect((play.arguments as Map)['rewind'], isTrue);
      await clip.dispose();
      await sub.cancel();
      expect(calls.last.method, 'dispose');
    });
  });

  group('pacat player', () {
    test('pipes the PCM to pacat and finishes when it exits', () async {
      final started = <_FakeProcess>[];
      final clip = PacatVoiceClip(
        wav,
        start: (exe, args) async {
          expect(exe, 'pacat');
          expect(args, containsAll(['--rate=16000', '--channels=1']));
          final p = _FakeProcess();
          started.add(p);
          return p;
        },
      );
      final done = clip.progress.firstWhere((p) => p.completed);
      await clip.play();
      await pumpEventQueue();
      expect(started.single.written, pcm);

      started.single.exit(0);
      expect((await done).completed, isTrue);
      await clip.dispose();
    });

    test('a pause stops pacat without marking the note finished', () async {
      final started = <_FakeProcess>[];
      final clip = PacatVoiceClip(
        wav,
        start: (_, _) async {
          final p = _FakeProcess();
          started.add(p);
          return p;
        },
      );
      await clip.play();
      await clip.pause();
      expect(started.single.killed, isTrue);
      await clip.play();
      expect(started, hasLength(2), reason: 'resumes in a new process');
      await clip.dispose();
    });

    // pacat이 뜨는 사이에 다시 누르거나(키 반복) 화면을 떠나도 프로세스가 고아로 안 남음
    test('a second play or a dispose while pacat starts leaves no stray '
        'process', () async {
      final started = <_FakeProcess>[];
      final gate = Completer<void>();
      final clip = PacatVoiceClip(
        wav,
        start: (_, _) async {
          await gate.future;
          final p = _FakeProcess();
          started.add(p);
          return p;
        },
      );
      final first = clip.play();
      final second = clip.play();
      final disposed = clip.dispose();
      gate.complete();
      await Future.wait([first, second, disposed]);
      expect(started, hasLength(1), reason: 'one process for one note');
      expect(started.single.killed, isTrue, reason: 'dispose reached it');
    });
  });
}

class _FakeProcess implements Process {
  final _exit = Completer<int>();
  final _sink = _Capture();
  late final IOSink _stdin = IOSink(_sink);
  bool killed = false;

  Uint8List get written => Uint8List.fromList(_sink.bytes);

  void exit(int code) => _exit.complete(code);

  @override
  IOSink get stdin => _stdin;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }
}

class _Capture implements StreamConsumer<List<int>> {
  final List<int> bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}
}
