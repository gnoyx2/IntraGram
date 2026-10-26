import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/chat/widgets/sas_fingerprint_dialog.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/scripted_inbound.dart';
import 'support/test_identities.dart';

// 숫자가 다르다는 확인은 무시되지 않음: 링크를 바로 닫고 경고 줄을 남기며, 대화상자에는 그 출구가 늘 있음
void main() {
  group('reportSasMismatch', () {
    late InMemoryStore store;
    late LinkRegistry registry;

    setUp(() {
      store = InMemoryStore();
      registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: testIdentity('a', alias: 'me', platform: 'test'),
      );
      addTearDown(() async {
        await registry.disposeAll();
        store.dispose();
      });
    });

    test('closes the link and leaves a warning line', () async {
      await connectScriptedInbound(
        registry,
        host: '192.168.1.20',
        identity: testIdentity('b'),
      );
      final id = store.conversations.single.id;
      expect(registry.linkFor(id)?.isSecure, isTrue);
      store
        ..setLocalVerified(id)
        ..setPeerVerified(id);

      await registry.reportSasMismatch(id);
      await pumpEventQueue(times: 30);

      expect(registry.linkFor(id)?.isClosed ?? true, isTrue);
      // 다시 붙어도 예전 확인이 이어지지 않게 지워짐
      expect(store.conversation(id)!.localVerified, isFalse);
      expect(store.conversation(id)!.online, isFalse);
      expect(
        store.messages(id).map((m) => m.systemEvent?.kind),
        contains(SystemEventKind.sasMismatch),
      );
    });
  });

  group('security code dialog', () {
    Future<List<SasOutcome?>> open(WidgetTester tester) async {
      final results = <SasOutcome?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showSasFingerprintDialog(
                  context,
                  peerAlias: 'bob',
                  sas: '123456',
                  localVerified: false,
                  verified: false,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('offers a mismatch exit next to the match button', (
      tester,
    ) async {
      final results = await open(tester);
      expect(find.text('They match'), findsOne);
      expect(find.text('Copy'), findsNothing, reason: 'no copying into chat');
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining("Don't send the code"), findsOne);
      expect(find.bySemanticsLabel('1 2 3, 4 5 6'), findsOne);

      await tester.tap(find.text('Codes differ'));
      await tester.pumpAndSettle();
      expect(results, [SasOutcome.mismatched]);
    });

    testWidgets('a match still returns matched', (tester) async {
      final results = await open(tester);
      await tester.tap(find.text('They match'));
      await tester.pumpAndSettle();
      expect(results, [SasOutcome.matched]);
    });

    // 상대 화면의 코드를 찍어 맞추는 길은 카메라가 있는 폰에만 둠 (플랫폼은 호스트가 아니라 대상 플랫폼)
    testWidgets(
      'a phone can scan the other screen instead',
      (tester) async {
        await open(tester);
        expect(find.text('Scan their code'), findsOne);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );

    testWidgets('a desktop has no scan button', (tester) async {
      await open(tester);
      expect(find.text('Scan their code'), findsNothing);
      expect(find.text('They match'), findsOne);
    }, variant: TargetPlatformVariant.desktop());
  });
}
