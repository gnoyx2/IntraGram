import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_commands.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/store/vault.dart';

import 'ui/_harness.dart';

void main() {
  test('text scale steps through the list and survives the saved file', () {
    expect(stepTextScale(1.0, 1), 1.15);
    expect(stepTextScale(2.0, 1), 2.0);
    expect(stepTextScale(0.85, -1), 0.85);
    expect(stepTextScale(1.5, 0), 1.0);
    expect(stepTextScale(1.23, 1), 1.15);

    const s = VaultSettings(textScale: 1.3);
    expect(VaultSettings.fromJson(s.toJson()).textScale, 1.3);
    expect(const VaultSettings().toJson().containsKey('textScale'), isFalse);
    expect(VaultSettings.fromJson({'textScale': 2}).textScale, 2.0);
    expect(VaultSettings.fromJson({'textScale': 9.0}).textScale, 1.0);
    expect(VaultSettings.fromJson({'textScale': 'x'}).textScale, 1.0);
  });

  testWidgets('Cmd+= and Cmd+0 ask for a bigger text and a reset', (
    tester,
  ) async {
    final steps = <int>[];
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        builder: (context, child) => AppCommands(
          navigatorKey: key,
          unlocked: true,
          onNewConnection: (_) {},
          onTextSize: steps.add,
          child: child!,
        ),
        home: const Focus(autofocus: true, child: SizedBox()),
      ),
    );
    await tester.pump();
    Future<void> press(LogicalKeyboardKey k, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    }

    await press(LogicalKeyboardKey.equal);
    await press(LogicalKeyboardKey.equal, shift: true);
    await press(LogicalKeyboardKey.minus);
    await press(LogicalKeyboardKey.digit0);
    expect(steps, [1, 1, -1, 0]);
  });

  testWidgets('desktop settings offer a text size, phones do not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const SettingsScreen()));
    await tester.pump();
    expect(find.text('Text size'), findsNothing);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(h.wrap(const SettingsScreen()));
    await tester.pump();
    expect(find.text('Shortcuts: ⌘+ · ⌘− · ⌘0'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
