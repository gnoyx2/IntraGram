import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/voice/voice_clip.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/transfer_tile.dart';
import 'package:intragram/features/chat/voice_recorder.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

void main() {
  testWidgets('loading voice cannot be activated twice', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final initialized = Completer<void>();
    var haptics = 0;
    var initializations = 0;
    debugVoiceClipLoader = (_) async {
      initializations++;
      await initialized.future;
      throw StateError('test');
    };
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate' &&
          call.arguments == 'HapticFeedbackType.lightImpact') {
        haptics++;
      }
      return null;
    });
    addTearDown(() {
      debugVoiceClipLoader = null;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
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
    final button = find.widgetWithIcon(IconButton, Icons.play_arrow_rounded);
    final activate = tester.widget<IconButton>(button).onPressed!;
    activate();
    activate();
    await tester.pump();
    expect(haptics, 1);
    final loading = find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(loading).onPressed, isNull);
    expect(initializations, 1);
    initialized.complete();
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('transfer progress fits a phone bubble with large text', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertTransfer(
      const FileTransfer(
        id: 't1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'movie.mkv',
        totalBytes: 10 * 1024 * 1024,
        transferredBytes: 2 * 1024 * 1024,
        state: TransferState.transferring,
        bytesPerSecond: 38.4 * 1024 * 1024,
      ),
    );
    await tester.pumpWidget(
      h.wrap(
        Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(3),
              disableAnimations: true,
            ),
            child: const SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 210,
                  child: TransferTile(
                    transferId: 't1',
                    mine: false,
                    onBubble: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  });

  testWidgets('an offered voice note says what it is before accepting', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertTransfer(
      const FileTransfer(
        id: 'v1',
        conversationId: 'c1',
        direction: TransferDirection.incoming,
        fileName: 'voice.wav',
        totalBytes: 48 * 1024,
        voice: true,
      ),
    );
    await tester.pumpWidget(
      h.wrap(
        const Scaffold(
          body: Center(
            child: TransferTile(
              transferId: 'v1',
              mine: false,
              onBubble: Colors.black,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 자동 수락이 기본으로 꺼져 있어 수락 버튼만 덩그러니 남으면 무엇을 받는지 모름
    expect(find.text('Voice message'), findsOneWidget);
    expect(find.text('49.2 KB'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('a declined image is quoted with its badge, not the thumbnail', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    // 1x1 투명 PNG
    final thumb = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..upsertTransfer(
        FileTransfer(
          id: 't1',
          conversationId: 'c1',
          direction: TransferDirection.incoming,
          fileName: 'photo.png',
          totalBytes: 2048,
          mimeType: 'image/png',
          thumbBytes: thumb,
          state: TransferState.rejected,
        ),
      )
      ..addMessage(
        msg(
          id: 'f',
          dir: MessageDirection.incoming,
          kind: MessageKind.file,
          transferId: 't1',
        ),
      )
      ..addMessage(
        msg(
          id: 'r',
          dir: MessageDirection.outgoing,
          text: 'no thanks',
          replyToId: 'f',
        ),
      );

    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await settleThumbCheck(tester);

    expect(find.text('no thanks'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
