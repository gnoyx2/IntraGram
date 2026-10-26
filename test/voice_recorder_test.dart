import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/voice_recorder.dart';

// 실제 파일·마이크 I/O 없이 메모리 바이트를 바로 돌려주는 가짜 녹음 백엔드
class _FakeCapture implements VoiceCapture {
  _FakeCapture(this._bytes);
  final List<int> _bytes;
  var started = false;
  var finished = false;
  var cancelled = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async => started = true;

  @override
  Future<Uint8List?> finish() async {
    finished = true;
    return Uint8List.fromList(_bytes);
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}

  @override
  Stream<double> get amplitudeStream => const Stream<double>.empty();
}

// 권한 확인이 끝날 때까지 [hasPermission]이 안 끝나는 가짜 백엔드: "권한
// 대기 중 취소" 경합을 재현하려고 그 시점을 테스트가 직접 쥠
class _DelayedPermissionCapture implements VoiceCapture {
  _DelayedPermissionCapture(this._bytes);
  final List<int> _bytes;
  final _permission = Completer<bool>();
  var started = false;
  var finished = false;
  var cancelled = false;

  void grantPermission() => _permission.complete(true);

  @override
  Future<bool> hasPermission() => _permission.future;

  @override
  Future<void> start() async => started = true;

  @override
  Future<Uint8List?> finish() async {
    finished = true;
    return Uint8List.fromList(_bytes);
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}

  @override
  Stream<double> get amplitudeStream => const Stream<double>.empty();
}

Future<void> _pumpButton(WidgetTester tester, VoiceRecorderButton button) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: button)),
    ),
  );
}

// 롱프레스 시작 → 800ms+ 유지(700ms 문턱 통과) → (옵션) 슬라이드 → 떼기
Future<void> _holdRelease(WidgetTester tester, {Offset? slide}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecorderButton)),
  );
  await tester.pump(const Duration(milliseconds: 800)); // 롱프레스 판정 시점
  await tester.pump();
  await tester.pump();
  // 700ms 문턱이 실제 Stopwatch(벽시계)를 읽으므로 fake clock의 pump(duration)으로는
  // 채울 수 없어 runAsync 안에서 실제 시간을 대기함
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 800)),
  );
  await tester.pump();
  if (slide != null) {
    await gesture.moveBy(slide);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('hold then release delivers the recorded bytes', (tester) async {
    final capture = _FakeCapture(List<int>.filled(4096, 7));
    Uint8List? got;
    await _pumpButton(
      tester,
      VoiceRecorderButton(
        enabled: true,
        onRecorded: (b) => got = b,
        createCapture: () => capture,
      ),
    );

    await _holdRelease(tester);

    expect(capture.started, isTrue);
    expect(capture.finished, isTrue);
    expect(got, isNotNull);
    expect(got!.length, 4096);
  });

  testWidgets('sliding up past the threshold cancels — nothing sent', (
    tester,
  ) async {
    final capture = _FakeCapture(List<int>.filled(4096, 7));
    var calls = 0;
    await _pumpButton(
      tester,
      VoiceRecorderButton(
        enabled: true,
        onRecorded: (_) => calls++,
        createCapture: () => capture,
      ),
    );

    await _holdRelease(tester, slide: const Offset(0, -120));

    expect(capture.started, isTrue);
    expect(capture.cancelled, isTrue);
    expect(capture.finished, isFalse);
    expect(calls, 0);
  });

  testWidgets('a plain tap starts hands-free (tap-locked) recording', (
    tester,
  ) async {
    final capture = _FakeCapture(List<int>.filled(4096, 7));
    await _pumpButton(
      tester,
      VoiceRecorderButton(
        enabled: true,
        onRecorded: (_) {},
        createCapture: () => capture,
      ),
    );

    await tester.tap(find.byType(VoiceRecorderButton));
    await tester.pump();
    await tester.pump();

    expect(capture.started, isTrue);
    // 탭-고정 녹음 중엔 마이크 대신 X(취소) 아이콘: 배너에도 같은 아이콘의
    // 취소 버튼이 따로 뜨므로(체크/전송 버튼과 짝) 최소 1개만 확인함
    expect(find.byIcon(Icons.close), findsWidgets);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('tapping the X while tap-locked cancels without sending', (
    tester,
  ) async {
    final capture = _FakeCapture(List<int>.filled(4096, 7));
    var calls = 0;
    await _pumpButton(
      tester,
      VoiceRecorderButton(
        enabled: true,
        onRecorded: (_) => calls++,
        createCapture: () => capture,
      ),
    );

    await tester.tap(find.byType(VoiceRecorderButton));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byType(VoiceRecorderButton));
    await tester.pump();
    await tester.pump();

    expect(capture.cancelled, isTrue);
    expect(capture.finished, isFalse);
    expect(calls, 0);
  });

  testWidgets(
    'a PointerCancel while permission is still pending never turns into a '
    'send once permission resolves',
    (tester) async {
      final capture = _DelayedPermissionCapture(List<int>.filled(4096, 7));
      var calls = 0;
      await _pumpButton(
        tester,
        VoiceRecorderButton(
          enabled: true,
          onRecorded: (_) => calls++,
          createCapture: () => capture,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoiceRecorderButton)),
      );
      await tester.pump(const Duration(milliseconds: 800)); // 홀드 판정 시점
      await tester.pump(); // _start 진입 후 hasPermission()에서 막힘

      // 시스템이 제스처를 가로채는 명시적 취소 신호(예: 스크롤 아레나 패배):
      // send/cancel 구분을 잃고 전송으로 처리되면 안 됨
      await gesture.cancel();
      await tester.pump();

      // 권한이 뒤늦게 허용됨: 이미 취소가 확정된 뒤이니 마이크가 잠깐
      // 열리더라도 바로 닫히고, 절대 onRecorded로 이어지면 안 됨
      capture.grantPermission();
      await tester.pump();
      await tester.pump();

      expect(capture.cancelled, isTrue);
      expect(capture.finished, isFalse);
      expect(calls, 0);
    },
  );
}
