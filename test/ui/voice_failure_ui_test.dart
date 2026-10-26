import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/voice/pacat_voice_clip.dart';
import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/features/chat/transfer_tile.dart';
import 'package:intragram/features/chat/voice_recorder.dart';
import 'package:intragram/store/models.dart';

import '../support/audio_process.dart';
import '_harness.dart';

// 녹음 도구가 도중에 끝난 백엔드: 파형 스트림에 오류가 오고 finish는 잘린 녹음 대신 예외를 던짐
class _DyingCapture implements VoiceCapture {
  final _amplitude = StreamController<double>.broadcast();
  var finished = false;

  void die() => _amplitude.addError(
    const ProcessException('pw-record', [], 'recording ended early'),
  );

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<Uint8List?> finish() async {
    finished = true;
    throw const ProcessException('pw-record', [], 'recording ended early');
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _amplitude.close();

  @override
  Stream<double> get amplitudeStream => _amplitude.stream;
}

void main() {
  testWidgets('a recorder that dies mid-recording stops at once and says '
      'nothing was saved', (tester) async {
    final capture = _DyingCapture();
    final sent = <Uint8List>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VoiceRecorderButton(
              enabled: true,
              onRecorded: sent.add,
              createCapture: () => capture,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecorderButton)),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump();
    capture.die();
    await tester.pump();
    await tester.pump();
    expect(capture.finished, isTrue, reason: 'stopped without a release');
    expect(find.text('Could not save the recording.'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(sent, isEmpty);
  });

  testWidgets('playback whose outputs both die shows an error instead of '
      'finishing', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    final started = <String, AudioProcess>{};
    debugVoiceClipLoader = (wav) async => PacatVoiceClip(
      wav,
      start: (executable, arguments) async {
        if (arguments.contains('--help')) return AudioProcess.help();
        return started[executable] = AudioProcess();
      },
    );
    addTearDown(() => debugVoiceClipLoader = null);
    final bytes = encodePcm16WavForTesting(Uint8List(32000));
    h.store.upsertTransfer(
      FileTransfer(
        id: 't1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'voice.wav',
        totalBytes: bytes.length,
        voice: true,
        voiceBytes: bytes,
        state: TransferState.complete,
      ),
    );
    await tester.pumpWidget(
      h.wrap(
        const Scaffold(
          body: Center(
            child: TransferTile(
              transferId: 't1',
              mine: false,
              onBubble: Colors.black,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump();
    started['pacat']!.exitWith(1);
    await tester.pump();
    await tester.pump();
    started['pw-play']!.exitWith(1);
    await tester.pump();
    await tester.pump();
    expect(find.text('Cannot play this voice message'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    // 완료(처음부터 다시)가 아니라 멈춘 자리에서 다시 누를 수 있는 재생 버튼
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
