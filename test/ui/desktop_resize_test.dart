import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/chat/widgets/drop_overlay.dart';
import 'package:intragram/features/chat/widgets/sas_fingerprint_dialog.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/home/widgets/conversation_tile.dart';
import 'package:intragram/features/home/widgets/manual_connect_dialog.dart';
import 'package:intragram/features/settings/pin_dialog.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/theme/app_theme.dart';

import '_harness.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} resizing preserves chat draft and drop area',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(420, 560);
        addTearDown(tester.view.reset);
        final h = Harness();
        addTearDown(h.dispose);
        h.store
          ..upsertConversation(conv('c1'))
          ..addMessage(
            msg(
              id: 'm1',
              dir: MessageDirection.incoming,
              text:
                  'A long desktop message that must wrap within the chat column. ' *
                  8,
            ),
          );
        await tester.pumpWidget(h.wrap(const HomeScreen()));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(ConversationTile));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.enterText(
          find.byType(TextField).last,
          'draft\nsecond line',
        );
        final state = tester.state(find.byType(ChatRoomScreen));
        for (final size in [
          const Size(600, 560),
          const Size(840, 650),
          const Size(1100, 760),
          const Size(1280, 800),
          const Size(420, 560),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.state(find.byType(ChatRoomScreen)), same(state));
          expect(find.text('draft\nsecond line'), findsOneWidget);
          final drop = tester.getRect(find.byType(DropOverlay));
          expect(drop.left, greaterThanOrEqualTo(0));
          expect(drop.right, lessThanOrEqualTo(size.width));
          expect(drop.bottom, lessThanOrEqualTo(size.height));
          expect(tester.takeException(), isNull, reason: '$platform $size');
        }
        await tester.pumpWidget(h.wrap(const SettingsScreen()));
        await tester.pump();
        final keys = find.textContaining(
          platform == TargetPlatform.macOS ? '⌘+' : 'Ctrl++',
        );
        await tester.scrollUntilVisible(keys, 200);
        expect(keys, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({platform}),
    );

    // 최소 창에서 고대비와 글자 확대를 같이 켜도 화면·드롭 영역·대화상자가 넘치지 않고, 그 상태로 늘렸다 줄여도 같음
    testWidgets(
      '${platform.name} minimum window with high contrast and large text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final h = Harness();
        addTearDown(h.dispose);
        h.store
          ..upsertConversation(conv('c1'))
          ..addMessage(
            msg(
              id: 'm1',
              dir: MessageDirection.incoming,
              text: 'High contrast and large text in a small window. ' * 6,
            ),
          );
        for (final scale in [1.3, 2.0]) {
          Widget scaled(Widget child) => h.wrap(
            child,
            builder: (context, child) => Theme(
              data: AppTheme.light(highContrast: true),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  highContrast: true,
                ),
                child: child!,
              ),
            ),
          );
          tester.view.physicalSize = const Size(420, 560);
          // 앞 반복에서 연 대화상자·화면이 남지 않게 앱을 새로 띄움
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(scaled(const HomeScreen()));
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull, reason: 'home $scale');
          // 2배 글자에선 목록이 첫 화면 아래로 내려가서 스크롤해서 엶 (넘침이 아님)
          await tester.ensureVisible(find.byType(ConversationTile));
          await tester.pump();
          await tester.tap(find.byType(ConversationTile));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          for (final size in [
            const Size(420, 560),
            const Size(1100, 760),
            const Size(420, 560),
            const Size(1280, 800),
            const Size(420, 560),
          ]) {
            tester.view.physicalSize = size;
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            final drop = tester.getRect(find.byType(DropOverlay));
            expect(drop.right, lessThanOrEqualTo(size.width));
            expect(drop.bottom, lessThanOrEqualTo(size.height));
            expect(tester.takeException(), isNull, reason: 'chat $scale $size');
          }
          await tester.pumpWidget(scaled(const SettingsScreen()));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'settings $scale');
          for (final open in <void Function(BuildContext)>[
            (c) => showDialog<void>(
              context: c,
              builder: (_) => const ManualConnectDialog(),
            ),
            (c) => PinDialog.show(c, alreadySet: false),
            (c) => showSasFingerprintDialog(
              c,
              peerAlias: 'bob-owl-22',
              sas: '123456',
              localVerified: false,
              verified: false,
            ),
          ]) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              scaled(
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => open(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('open'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 500));
            expect(find.byType(Dialog), findsOneWidget);
            expect(tester.takeException(), isNull, reason: 'dialog $scale');
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}
