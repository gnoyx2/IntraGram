import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/private_dir.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

class _FakePicker extends FilePickerPlatform {
  Completer<String?> answer = Completer<String?>();
  int asked = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    asked++;
    return answer.future;
  }
}

Future<Harness> _pumpVoiceTile(WidgetTester tester) async {
  final h = Harness();
  addTearDown(h.dispose);
  h.store
    ..upsertConversation(conv('c1', secure: true, verified: true))
    ..upsertTransfer(
      FileTransfer(
        id: 'v1',
        conversationId: 'c1',
        direction: TransferDirection.outgoing,
        fileName: 'voice-note.wav',
        totalBytes: 64,
        voice: true,
        voiceBytes: Uint8List.fromList(List.filled(64, 1)),
        state: TransferState.complete,
        mimeType: 'audio/wav',
      ),
    )
    ..addMessage(
      msg(
        id: 'm1',
        dir: MessageDirection.outgoing,
        kind: MessageKind.file,
        transferId: 'v1',
      ),
    );
  await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
  await tester.pump();
  await tester.pump();
  return h;
}

// 위젯 테스트의 가짜 시계 안에서 진짜 파일 I/O를 끝까지 굴림: I/O 완료 콜백이
// 가짜 zone의 마이크로태스크라서, 실시간으로 잠깐 기다린 뒤 pump하기를 조건이 될
// 때까지 반복함
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxTries = 100,
}) async {
  for (var i = 0; i < maxTries && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakePicker picker;
  late Directory dir;
  // 데스크톱 폴더 선택은 고른 폴더를 앱 지원 폴더의 설정 파일에 기록함
  // privateAppDir는 경로 Future를 캐시함: 가짜 시계 밖에서 미리 풀어 둬야
  // 끝난 테스트의 zone에 묶인 채 다음 테스트가 영영 기다리지 않음
  late Directory support;
  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('intragram_voice_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => support.path,
        );
    await privateAppDir();
  });
  tearDownAll(() => support.deleteSync(recursive: true));
  setUp(() {
    picker = _FakePicker();
    FilePickerPlatform.instance = picker;
    dir = Directory.systemTemp.createTempSync('intragram_voice_save_');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('a folder chosen after the tile closed writes nothing', (
    tester,
  ) async {
    await _pumpVoiceTile(tester);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(picker.asked, 1, reason: 'the chooser is open');

    await tester.pumpWidget(const SizedBox()); // 선택기가 열린 채 화면이 닫힘
    // 아직 없는 폴더를 골랐다면, 저장을 시도만 해도 폴더가 생겨 버림: 화면이 닫혔으면
    // 폴더 자체가 만들어지면 안 됨(예약 전에 다시 확인함)
    final chosen = Directory('${dir.path}/never-created');
    picker.answer.complete(chosen.path);
    // 잘못 구현됐다면 폴더가 만들어질 때까지(몇 번의 I/O 라운드) 충분히 기다려 봄
    await _pumpUntil(tester, () => chosen.existsSync(), maxTries: 15);

    expect(chosen.existsSync(), isFalse, reason: 'nothing was even reserved');
    expect(dir.listSync(), isEmpty, reason: 'no bytes, no partial');
  });

  testWidgets('a failed save is shown to the user and leaves nothing', (
    tester,
  ) async {
    await _pumpVoiceTile(tester);
    final notADirectory = File('${dir.path}/blocker')..writeAsStringSync('x');

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    picker.answer.complete(notADirectory.path); // 폴더가 아니라 파일을 고른 셈
    await _pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);

    expect(find.text('Save failed'), findsOneWidget);
    expect(dir.listSync().map((e) => e.path), [notADirectory.path]);
  });

  testWidgets('a successful save shows where the file went', (tester) async {
    await _pumpVoiceTile(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    picker.answer.complete(dir.path);
    await _pumpUntil(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);

    expect(find.textContaining('Saved to'), findsOneWidget);
    final saved = dir.listSync().whereType<File>().single;
    expect(saved.path, endsWith('.wav'));
    expect(saved.readAsBytesSync(), List.filled(64, 1));
  });
}
