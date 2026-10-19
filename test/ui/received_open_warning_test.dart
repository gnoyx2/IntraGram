import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// 데스크톱에서 받은 파일 열기: 프로그램과 인터넷에 닿는 형식은 바로 열지 않고 먼저 물음
void main() {
  const en = S(AppLang.en);

  Future<void> pumpReceived(WidgetTester tester, String name) async {
    final dir = Directory.systemTemp.createTempSync('recv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/$name')..writeAsStringSync('x');
    final h = Harness();
    addTearDown(h.dispose);
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
          fileName: name,
          totalBytes: 1,
          transferredBytes: 1,
          localPath: file.path,
          state: TransferState.complete,
        ),
      );
    await tester.pumpWidget(h.wrap(const ChatRoomScreen(conversationId: 'c1')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text(en.t('transfer.open')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a received web page asks before opening',
    (tester) async {
      await pumpReceived(tester, 'invite.html');
      expect(find.text(en.t('transfer.netWarnTitle')), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a received program asks before running',
    (tester) async {
      await pumpReceived(tester, 'setup.command');
      expect(find.text(en.t('transfer.execWarnTitle')), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
