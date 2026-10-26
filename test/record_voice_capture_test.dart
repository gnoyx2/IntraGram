import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/features/chat/voice_recorder.dart';

import 'support/audio_process.dart';

void main() {
  test(
    'PCM pieces are wiped even after the recording limit is reached',
    () async {
      final previous = RecordPlatform.instance;
      final platform = _RecordPlatform();
      RecordPlatform.instance = platform;
      addTearDown(() => RecordPlatform.instance = previous);
      final capture = RecordVoiceCapture();
      addTearDown(capture.dispose);
      await capture.start();

      const limit = kMaxVoiceNoteSeconds * kVoiceSampleRate * 2;
      final first = Uint8List.fromList([1, 2, 3, 4]);
      final clipped = Uint8List(limit - 2)..fillRange(0, limit - 2, 9);
      final discarded = Uint8List.fromList([5, 6]);
      for (final piece in [first, clipped, discarded]) {
        platform.pcm.add(piece);
        await pumpEventQueue();
        expect(piece.every((byte) => byte == 0), isTrue);
      }

      final wav = (await capture.finish())!;
      expect(wav.length, 44 + limit);
      expect(wav.sublist(44, 48), [1, 2, 3, 4]);
      expect(wav.skip(48).every((byte) => byte == 9), isTrue);
    },
  );
  group('Linux recording', () {
    test(
      'missing parecord records PipeWire PCM in memory and wipes chunks',
      () async {
        final tools = _Recorders(missing: {'parecord'});
        final capture = _capture(tools);
        final amplitudes = <double>[];
        final sub = capture.amplitudeStream.listen(amplitudes.add);
        final chunk = Uint8List.fromList([1, 2, 3, 4]);
        final started = capture.start();
        await pumpEventQueue();
        tools.started['pw-record']!.output.add(chunk);
        await started;
        await pumpEventQueue();
        expect(chunk, [0, 0, 0, 0]);
        expect(amplitudes.single, lessThan(0));
        final wav = (await capture.finish())!;
        expect(wav.sublist(44), [1, 2, 3, 4]);
        expect(tools.calls, ['parecord', 'pw-record']);
        expect(tools.started['pw-record']!.killed, isTrue);
        await sub.cancel();
      },
    );

    test('parecord without a server falls back to pw-record before '
        'recording starts', () async {
      final tools = _Recorders(noServer: {'parecord'});
      final capture = _capture(tools);
      final started = capture.start();
      await pumpEventQueue();
      expect(tools.calls, ['parecord', 'pw-record']);
      tools.started['pw-record']!.output.add(Uint8List.fromList([5, 6]));
      await started;
      expect((await capture.finish())!.sublist(44), [5, 6]);
    });

    test('both tools failing before any PCM fails the start once', () async {
      final tools = _Recorders(noServer: {'parecord', 'pw-record'});
      final capture = _capture(tools);
      await expectLater(capture.start(), throwsA(isA<ProcessException>()));
      expect(tools.calls, ['parecord', 'pw-record']);
    });

    test(
      'a tool that dies mid-recording is an error and nothing is sent',
      () async {
        final tools = _Recorders();
        final capture = _capture(tools);
        final errors = <Object>[];
        final sub = capture.amplitudeStream.listen((_) {}, onError: errors.add);
        await _startWith(capture, tools, 'parecord', [1, 2, 3, 4]);
        tools.started['parecord']!.exitWith(1);
        await pumpEventQueue();
        expect(errors.single, isA<ProcessException>());
        await expectLater(capture.finish(), throwsA(isA<ProcessException>()));
        expect(tools.calls, ['parecord'], reason: 'a gap cannot be retried');
        await sub.cancel();
      },
    );

    for (final stop in ['cancel', 'finish']) {
      test('a user $stop never starts a fallback', () async {
        final tools = _Recorders();
        final capture = _capture(tools);
        final errors = <Object>[];
        final sub = capture.amplitudeStream.listen((_) {}, onError: errors.add);
        await _startWith(capture, tools, 'parecord', [1, 2]);
        if (stop == 'cancel') {
          await capture.cancel();
        } else {
          expect((await capture.finish())!.sublist(44), [1, 2]);
        }
        await pumpEventQueue();
        expect(tools.calls, ['parecord']);
        expect(errors, isEmpty);
        expect(tools.started['parecord']!.killed, isTrue);
        await sub.cancel();
      });
    }

    test('a silent tool that stays up counts as started after a second', () {
      final tools = _Recorders();
      final capture = _capture(tools);
      final errors = <Object>[];
      fakeAsync((async) {
        capture.amplitudeStream.listen((_) {}, onError: errors.add);
        var started = false;
        capture.start().then((_) => started = true);
        async.flushMicrotasks();
        expect(started, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(started, isTrue);
        tools.started['parecord']!.exitWith(1);
        async.flushMicrotasks();
        expect(tools.calls, ['parecord'], reason: 'too late for a fallback');
        expect(errors.single, isA<ProcessException>());
      });
    });
  });
}

// 도구 이름별 가짜 프로세스. noServer는 첫 PCM 전에 1로 끝나는 도구(서버에 못 붙음), missing은 ENOENT
class _Recorders {
  _Recorders({this.missing = const {}, this.noServer = const {}});
  final Set<String> missing;
  final Set<String> noServer;
  final calls = <String>[];
  final started = <String, AudioProcess>{};

  Future<Process> call(String executable, List<String> arguments) async {
    if (arguments.contains('--help')) return AudioProcess.help();
    calls.add(executable);
    if (missing.contains(executable)) {
      throw ProcessException(executable, arguments, 'missing', 2);
    }
    final process = started[executable] = AudioProcess();
    if (noServer.contains(executable)) {
      scheduleMicrotask(() => process.exitWith(1));
    }
    return process;
  }
}

RecordVoiceCapture _capture(_Recorders tools) {
  final previous = RecordPlatform.instance;
  RecordPlatform.instance = _RecordPlatform();
  addTearDown(() => RecordPlatform.instance = previous);
  final capture = RecordVoiceCapture(linuxStart: tools.call);
  addTearDown(capture.dispose);
  return capture;
}

// 시작은 첫 PCM이 와야 끝남: 그 조각을 흘려 보내며 기다림
Future<void> _startWith(
  RecordVoiceCapture capture,
  _Recorders tools,
  String executable,
  List<int> pcm,
) async {
  final started = capture.start();
  await pumpEventQueue();
  tools.started[executable]!.output.add(Uint8List.fromList(pcm));
  await started;
}

class _RecordPlatform extends RecordPlatform {
  final pcm = StreamController<Uint8List>();
  // Linux 경로는 플러그인 스트림을 안 씀: 듣는 쪽이 없으면 close가 안 끝나서 dispose 때 대신 들음
  bool streamed = false;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    streamed = true;
    return pcm.stream;
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  Future<String?> stop(String recorderId) async {
    await pcm.close();
    return null;
  }

  @override
  Future<void> dispose(String recorderId) {
    if (!streamed) pcm.stream.listen((_) {});
    return pcm.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
