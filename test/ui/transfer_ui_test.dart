import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 1x1 투명 PNG (썸네일 테스트용으로 진짜 디코드 가능한 이미지)
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('an offered incoming image transfer shows a preview thumbnail', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
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
          thumbBytes: tinyPng,
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await settleThumbCheck(tester);

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('a completed image transfer renders a thumbnail', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    final dir = Directory.systemTemp.createTempSync('intragram_thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final img = File('${dir.path}/photo.png')..writeAsBytesSync(tinyPng);

    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(
        msg(
          id: 'fm',
          dir: MessageDirection.incoming,
          kind: MessageKind.file,
          transferId: 'tp',
        ),
      )
      ..upsertTransfer(
        FileTransfer(
          id: 'tp',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'photo.png',
          totalBytes: img.lengthSync(),
          transferredBytes: img.lengthSync(),
          mimeType: 'image/png',
          localPath: img.path,
          state: TransferState.complete,
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump(); // transfers 스트림이 emit하게 함
    await settleThumbCheck(tester); // SafeFileImage의 헤더 검사가 끝나야 그림

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('file message renders a transfer tile with accept / decline', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..upsertTransfer(
        const FileTransfer(
          id: 't1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'photo.jpg',
          totalBytes: 2048,
        ),
      )
      ..addMessage(
        msg(
          id: 'm1',
          dir: MessageDirection.incoming,
          kind: MessageKind.file,
          transferId: 't1',
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.pump();
    expect(h.store.transfer('t1')!.state, TransferState.rejected);
  });

  testWidgets('transferring tile shows a kind icon and an ETA', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..upsertTransfer(
        const FileTransfer(
          id: 't1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'movie.mkv',
          totalBytes: 10 * 1024 * 1024,
          transferredBytes: 2 * 1024 * 1024,
          state: TransferState.transferring,
          bytesPerSecond: 1024 * 1024,
        ),
      )
      ..addMessage(
        msg(
          id: 'm1',
          dir: MessageDirection.incoming,
          kind: MessageKind.file,
          transferId: 't1',
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.movie_outlined), findsOneWidget); // FileKind.video
    expect(find.textContaining('left'), findsOneWidget); // 속도에서 계산한 ETA
  });

  testWidgets(
    'a failed outgoing voice upload shows the player AND a retry, not just the player',
    (tester) async {
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
            totalBytes: 4096,
            voice: true,
            voiceBytes: Uint8List.fromList(List.filled(64, 1)),
            state: TransferState.failed,
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

      await tester.pumpWidget(
        h.wrap(const ChatRoomScreen(conversationId: 'c1')),
      );
      await tester.pump();
      await tester.pump();

      // 재생 가능(바이트 있음)해도 실패 상태는 숨겨지면 안 됨
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('Voice message failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
}
