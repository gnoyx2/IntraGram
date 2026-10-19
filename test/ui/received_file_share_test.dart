import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/store/models.dart';

import '_harness.dart';

// Android 앱 전용 폴더에 받은 파일은 파일 관리자에 안 보여서, 받은 타일의 공유 시트가
// 유일한 출구(파일 앱·드라이브·다른 앱으로 저장)
void main() {
  const en = S(AppLang.en);

  testWidgets(
    'a file received on Android can be shared out',
    (tester) async {
      final shared = <MethodCall>[];
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        shared.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final dir = Directory.systemTemp.createTempSync('recv');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/report.pdf')..writeAsStringSync('%PDF');

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
            fileName: 'report.pdf',
            totalBytes: 4,
            transferredBytes: 4,
            mimeType: 'application/pdf',
            localPath: file.path,
            state: TransferState.complete,
          ),
        );
      await tester.pumpWidget(
        h.wrap(const ChatRoomScreen(conversationId: 'c1')),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text(en.t('transfer.shareSave')));
      await tester.pump();
      expect(shared, isNotEmpty);
      expect(shared.single.arguments.toString(), contains('report.pdf'));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
