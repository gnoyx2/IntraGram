import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/windows_clipboard.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';

import '_harness.dart';

// 붙여넣기 버튼은 클립보드 종류만 물어 띄우고(내용을 읽으면 iOS 허용 창·macOS 경고·Windows 임시 BMP)
// 내용은 버튼을 눌렀을 때만 읽음. Windows 이미지는 CF_DIB를 메모리에서 .bmp로 바꿈

Uint8List _dib({
  required int width,
  required int bitCount,
  int compression = 0,
  int colorsUsed = 0,
  required List<int> tail,
}) {
  final header = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, 1, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, bitCount, Endian.little)
    ..setUint32(16, compression, Endian.little)
    ..setUint32(32, colorsUsed, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...tail]);
}

Future<List<int>> _decode(WidgetTester tester, Uint8List bmp) async {
  final pixels = await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bmp);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData();
    return data!.buffer.asUint8List().toList();
  });
  return pixels!;
}

void main() {
  const privacy = MethodChannel('intragram/privacy');
  const pasteboard = MethodChannel('pasteboard');

  testWidgets('a clipboard DIB becomes a BMP the image codec reads', (
    tester,
  ) async {
    // 24비트: 빨강, 파랑 (BGR, 행은 4바이트 정렬)
    final rgb = _dib(
      width: 2,
      bitCount: 24,
      tail: [0, 0, 255, 255, 0, 0, 0, 0],
    );
    expect(await _decode(tester, dibToBmp(rgb)!), [
      ...[255, 0, 0, 255],
      ...[0, 0, 255, 255],
    ]);

    // 32비트 BI_BITFIELDS: 머리 뒤 마스크 12바이트, 초록 한 점
    final masks = ByteData(12)
      ..setUint32(0, 0x00FF0000, Endian.little)
      ..setUint32(4, 0x0000FF00, Endian.little)
      ..setUint32(8, 0x000000FF, Endian.little);
    final bitfields = _dib(
      width: 1,
      bitCount: 32,
      compression: 3,
      tail: [...masks.buffer.asUint8List(), 0, 255, 0, 0],
    );
    expect(await _decode(tester, dibToBmp(bitfields)!), [0, 255, 0, 255]);

    // 8비트 색표 2개: 1번(빨강)을 가리키는 점
    final indexed = _dib(
      width: 1,
      bitCount: 8,
      colorsUsed: 2,
      tail: [255, 0, 0, 0, 0, 0, 255, 0, 1, 0, 0, 0],
    );
    expect(await _decode(tester, dibToBmp(indexed)!), [255, 0, 0, 255]);

    expect(dibToBmp(Uint8List(10)), isNull);
  });

  testWidgets('the paste buttons come from the kind check, content only on '
      'tap', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    final pasteboardCalls = <String>[];
    messenger
      ..setMockMethodCallHandler(privacy, (call) async {
        if (call.method == 'clipboardKinds') {
          return <String, bool>{'image': true, 'files': false};
        }
        return null;
      })
      ..setMockMethodCallHandler(pasteboard, (call) async {
        pasteboardCalls.add(call.method);
        return null;
      })
      ..setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.hasStrings'
            ? <String, dynamic>{'value': false}
            : null,
      );
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(privacy, null)
        ..setMockMethodCallHandler(pasteboard, null)
        ..setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(pasteboardCalls, isEmpty, reason: 'nothing was read to show it');

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pump();
    expect(pasteboardCalls, ['image']);
  });

  test('without a kind check the platform reports null', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      privacy,
      (_) => throw MissingPluginException(),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(privacy, null));

    expect(await OsPrivacy.clipboardKinds(), isNull);
  });
}
