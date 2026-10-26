import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/search/search_screen.dart';
import 'package:intragram/widgets/press_scale.dart';

import '_harness.dart';

void main() {
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
