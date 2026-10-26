import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/audit/anchor_bundle.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/widgets/chat_app_bar.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';

import '../support/in_memory_store_fixtures.dart';
import '../support/test_identities.dart';

void main() {
  testWidgets('chat menu exports body-free evidence after a message burn', (
    tester,
  ) async {
    final store = (await tester.runAsync(() async {
      final store = InMemoryStore()..upsertConversation(conversation('c1'));
      store.evidence.bindSigner(testIdentity('a'));
      store.addMessage(incoming('message1'));
      store.userDeletesMessage('message1');
      await pumpEventQueue();
      return store;
    }))!;
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: testIdentity('a'),
    );
    addTearDown(() async {
      await registry.disposeAll();
      store.dispose();
    });
    String? clipboard;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('intragram/privacy'),
      (call) async {
        if (call.method == 'copySensitive') {
          clipboard = call.arguments as String;
        }
        return null;
      },
    );
    addTearDown(() async {
      await OsPrivacy.clearClipboard();
      messenger.setMockMethodCallHandler(
        const MethodChannel('intragram/privacy'),
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ChatOverflowMenu(
                conversation: store.conversation('c1')!,
                registry: registry,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audit & Merkle Proofs'));
    await tester.pumpAndSettle();
    expect(store.messageById('message1'), isNull);
    expect(find.text('Burn policy triggered'), findsOneWidget);
    expect(find.text('App resource cleanup completed'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Commit Merkle batch'));
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy JSON audit bundle'));
    await tester.tap(find.text('Copy JSON audit bundle'));
    await tester.pumpAndSettle();
    expect(clipboard, isNotNull);
    expect(clipboard, isNot(contains('secret')));
    final verdict = await tester.runAsync(() => verifyAnchorBundle(clipboard!));
    expect(verdict!.ok, isTrue);
    expect((jsonDecode(clipboard!) as Map)['entries'], hasLength(2));

    await tester.ensureVisible(
      find.text('Export / verify external anchor bundle'),
    );
    await tester.tap(find.text('Export / verify external anchor bundle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), clipboard!);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Verify audit bundle'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Verify audit bundle'));
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Bundle signatures and proofs verified'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(1), '{}');
    await tester.pump();
    expect(
      find.textContaining('Bundle signatures and proofs verified'),
      findsNothing,
    );
    await OsPrivacy.clearClipboard();
    expect(tester.takeException(), isNull);
  });
}
