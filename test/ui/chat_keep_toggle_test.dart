import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import '_harness.dart';

class _VaultOn extends VaultSettingsNotifier {
  @override
  VaultSettings build() => const VaultSettings(enabled: true);
}

Widget _opener() => Builder(
  builder: (context) => TextButton(
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ChatRoomScreen(conversationId: 'c1'),
      ),
    ),
    child: const Text('open'),
  ),
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('leaving a saved chat does not stop to ask, the menu decides', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store
      ..upsertConversation(conv('c1', secure: true, verified: true))
      ..addMessage(msg(id: 'm1', dir: MessageDirection.incoming, text: 'hi'));
    await tester.pumpWidget(
      h.wrap(
        _opener(),
        overrides: [vaultSettingsProvider.overrideWith(_VaultOn.new)],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await _openMenu(tester);
    await tester.tap(find.text('Keep on this device'));
    await tester.pumpAndSettle();
    expect(h.store.conversation('c1')!.vaultOptOut, isTrue);

    await _openMenu(tester);
    await tester.tap(find.text('Keep on this device'));
    await tester.pumpAndSettle();
    expect(h.store.conversation('c1')!.vaultOptOut, isFalse);

    // 시스템 뒤로(가장자리 스와이프와 같은 경로)가 대화상자 없이 바로 나감
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('no keep item when saving is off', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1', secure: true, verified: true));
    await tester.pumpWidget(h.wrap(_opener()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    expect(find.text('Keep on this device'), findsNothing);
  });
}
