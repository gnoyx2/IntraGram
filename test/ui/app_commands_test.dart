import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_commands.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/search/search_screen.dart';
import 'package:intragram/features/settings/settings_screen.dart';

import '_harness.dart';

Future<List<String>> _pump(WidgetTester tester, {bool unlocked = true}) async {
  final h = Harness();
  addTearDown(h.dispose);
  final key = GlobalKey<NavigatorState>();
  final calls = <String>[];
  await tester.pumpWidget(
    h.wrap(
      const Scaffold(body: Focus(autofocus: true, child: Text('home'))),
      navigatorKey: key,
      builder: (context, child) => AppCommands(
        navigatorKey: key,
        unlocked: unlocked,
        onNewConnection: (_) => calls.add('connect'),
        onTextSize: (step) => calls.add('size:$step'),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  return calls;
}

Future<void> _keys(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final k in keys) {
    await tester.sendKeyDownEvent(k);
  }
  for (final k in keys.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pumpAndSettle();
}

const _cmd = LogicalKeyboardKey.metaLeft;
const _ctrl = LogicalKeyboardKey.controlLeft;

void main() {
  testWidgets('Cmd+, opens settings once and Esc closes it', (tester) async {
    await _pump(tester);
    await _keys(tester, [_cmd, LogicalKeyboardKey.comma]);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await _keys(tester, [_cmd, LogicalKeyboardKey.comma]);
    expect(find.byType(SettingsScreen, skipOffstage: false), findsOneWidget);

    await _keys(tester, [LogicalKeyboardKey.escape]);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Ctrl+F opens search and Esc closes it from the text field', (
    tester,
  ) async {
    await _pump(tester);
    await _keys(tester, [_ctrl, LogicalKeyboardKey.keyF]);
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.showKeyboard(find.byType(TextField));

    await _keys(tester, [LogicalKeyboardKey.escape]);
    expect(find.byType(SearchScreen), findsNothing);
  });

  testWidgets('Cmd+W closes the page and Esc closes a dialog', (tester) async {
    await _pump(tester);
    await _keys(tester, [_cmd, LogicalKeyboardKey.comma]);
    await _keys(tester, [_cmd, LogicalKeyboardKey.keyW]);
    expect(find.byType(SettingsScreen), findsNothing);

    showDialog<void>(
      context: tester.element(find.text('home')),
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await tester.pumpAndSettle();
    await _keys(tester, [LogicalKeyboardKey.escape]);
    expect(find.text('dialog'), findsNothing);
  });

  testWidgets('Ctrl+N asks for a new connection, not while locked', (
    tester,
  ) async {
    final calls = await _pump(tester);
    await _keys(tester, [_ctrl, LogicalKeyboardKey.keyN]);
    expect(calls, ['connect']);
  });

  testWidgets('a locked app opens nothing', (tester) async {
    final calls = await _pump(tester, unlocked: false);
    await _keys(tester, [_ctrl, LogicalKeyboardKey.keyN]);
    await _keys(tester, [_cmd, LogicalKeyboardKey.comma]);
    expect(calls, isEmpty);
    expect(find.byType(SettingsScreen), findsNothing);
  });
  Future<void> menu(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'intragram/menu',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
  }

  testWidgets(
    'native menu uses the same connection, search, close and size commands',
    (tester) async {
      final calls = await _pump(tester);
      await menu('newConnection');
      await menu('textSize', 1);
      await menu('textSize', -1);
      await menu('textSize', 0);
      await menu('textSize', 99);
      expect(calls, ['connect', 'size:1', 'size:-1', 'size:0']);
      await menu('settings');
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await menu('close');
      await tester.pumpAndSettle();
      await menu('search');
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      await menu('close');
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      await _keys(tester, [_cmd, LogicalKeyboardKey.equal]);
      await _keys(tester, [_ctrl, LogicalKeyboardKey.minus]);
      await _keys(tester, [_cmd, LogicalKeyboardKey.digit0]);
      expect(calls.skip(4), ['size:1', 'size:-1', 'size:0']);
    },
  );

  testWidgets('native Find searches the focused chat just like Cmd+F', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.store.upsertConversation(conv('c1'));
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      h.wrap(
        const ChatRoomScreen(conversationId: 'c1'),
        navigatorKey: key,
        builder: (_, child) => AppCommands(
          navigatorKey: key,
          unlocked: true,
          onNewConnection: (_) {},
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField).last);
    await menu('search');
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.widgetWithText(TextField, 'Search in chat'), findsOneWidget);
  });
}
