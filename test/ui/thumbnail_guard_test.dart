import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 1x1 PNG의 IHDR 폭/높이만 바꾸고 CRC를 다시 맞춤. 헤더만 보면 거대한 캔버스
Uint8List hugePng(int side) {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );
  final view = ByteData.sublistView(png)
    ..setUint32(16, side)
    ..setUint32(20, side);
  view.setUint32(29, _crc32(png.sublist(12, 29)));
  return png;
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Future<void> pumpOffer(WidgetTester tester, Harness h, Uint8List thumb) async {
  h.store
    ..upsertConversation(conv('c1', secure: true, verified: true))
    ..addMessage(
      msg(
        id: 'om',
        dir: MessageDirection.incoming,
        kind: MessageKind.file,
        transferId: 'ot',
      ),
    )
    ..upsertTransfer(
      FileTransfer(
        id: 'ot',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'incoming.png',
        totalBytes: 999999,
        mimeType: 'image/png',
        thumbBytes: thumb,
      ),
    );
  await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
  await tester.pump();
  await settleThumbCheck(tester);
}

void main() {
  testWidgets('an oversized offered thumbnail is dropped before decode', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    await pumpOffer(tester, h, hugePng(20000));

    expect(find.byType(Image), findsNothing);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('a sane offered thumbnail still renders', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await pumpOffer(tester, h, hugePng(1));

    expect(find.byType(Image), findsOneWidget);
  });
}
