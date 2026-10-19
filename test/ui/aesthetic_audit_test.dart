import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/chat/chat_room_screen.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/search/search_screen.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/empty_state.dart';
import 'package:intragram/widgets/empty_state_art.dart';
import 'package:intragram/widgets/press_scale.dart';

import '_harness.dart';

void main() {
  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    final mode = theme.brightness.name;
    test('$mode desktop details follow tokens and interaction states', () {
      final scrollbar = theme.scrollbarTheme;
      expect(scrollbar.radius, const Radius.circular(AppRadius.pill));
      expect(scrollbar.thickness!.resolve({}), 4);
      expect(scrollbar.thickness!.resolve({WidgetState.hovered}), 6);
      expect(scrollbar.interactive, isTrue);
      final alpha = [
        for (final states in [
          <WidgetState>{},
          {WidgetState.hovered},
          {WidgetState.dragged},
        ])
          scrollbar.thumbColor!.resolve(states)!.a,
      ];
      expect(alpha[0], lessThan(alpha[1]));
      expect(alpha[1], lessThan(alpha[2]));
      expect(
        theme.tooltipTheme.padding,
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      );
    });

    for (final art in EmptyStateArt.values) {
      testWidgets('$mode $art empty state fits 200% text in a short viewport', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 240),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: EmptyState(
                  art: art,
                  title: '함께 대화를 시작해 보세요',
                  body: '같은 네트워크의 기기를 연결하면 안전하게 대화할 수 있어요.',
                  action: FilledButton(
                    onPressed: () {},
                    child: const Text('연결'),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
      });
    }

    for (final screen in <Widget>[
      const HomeScreen(),
      const ChatRoomScreen(conversationId: 'c1'),
      const SettingsScreen(),
      const SearchScreen(),
    ]) {
      testWidgets('$mode ${screen.runtimeType} fits a phone at 200%', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final h = Harness();
        addTearDown(h.dispose);
        h.store.upsertConversation(conv('c1', secure: true, verified: true));
        final dir = Directory.systemTemp.createTempSync('intragram_aesthetic');
        addTearDown(() => dir.deleteSync(recursive: true));
        const boundaryKey = ValueKey('audit-frame');
        await tester.pumpWidget(
          h.wrap(
            Theme(
              data: theme,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(key: boundaryKey, child: screen),
              ),
            ),
            overrides: [
              vaultProvider.overrideWithValue(
                Vault(resolveDir: () async => dir.path),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (screen is SettingsScreen) {
          await tester.scrollUntilVisible(
            find.byType(SegmentedButton<LargeMessageMode>),
            200,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        await tester.runAsync(() async {
          final frame = await boundary.toImage();
          final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
          final out = Directory('build/aesthetic_audit')
            ..createSync(recursive: true);
          File(
            '${out.path}/$mode-${screen.runtimeType}-200.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          frame.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    for (final size in [const Size(768, 1024), const Size(1440, 900)]) {
      for (final screen in <Widget>[
        const HomeScreen(),
        const ChatRoomScreen(conversationId: 'c1'),
      ]) {
        testWidgets('$mode ${screen.runtimeType} fits $size at 200%', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final h = Harness();
          addTearDown(h.dispose);
          h.store.upsertConversation(conv('c1'));
          await tester.pumpWidget(
            h.wrap(
              Theme(
                data: theme,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: screen,
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('large phone text keeps home actions reachable in the menu', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(
      h.wrap(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: HomeScreen(),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (final label in ['Search messages', 'Connect by IP', 'Guest portal']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Search messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('press feedback has no animation under Reduce Motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PressScale(
              child: TextButton(onPressed: () {}, child: const Text('tap')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    await tester.pump();
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.duration, Duration.zero);
    expect(scale.scale, 1);
    await tester.pumpAndSettle();
  });
}
