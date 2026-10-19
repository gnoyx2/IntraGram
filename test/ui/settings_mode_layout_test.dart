import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import '_harness.dart';

void main() {
  for (final (width, scale, direction) in [
    (390.0, 1.0, Axis.horizontal),
    (320.0, 2.0, Axis.vertical),
    (768.0, 2.0, Axis.horizontal),
  ]) {
    testWidgets('message mode remains selectable at $width/$scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = Harness();
      addTearDown(h.dispose);
      final dir = Directory.systemTemp.createTempSync('intragram_mode_layout');
      addTearDown(() => dir.deleteSync(recursive: true));
      await tester.pumpWidget(
        h.wrap(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(scale),
            ),
            child: const SettingsScreen(),
          ),
          overrides: [
            vaultProvider.overrideWithValue(
              Vault(resolveDir: () async => dir.path),
            ),
          ],
        ),
      );
      final modes = find.byType(SegmentedButton<LargeMessageMode>);
      await tester.scrollUntilVisible(modes, 200);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SegmentedButton<LargeMessageMode>>(modes).direction,
        direction,
      );
      await tester.ensureVisible(find.text('Unlimited'));
      await tester.tap(find.text('Unlimited'));
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedButton<LargeMessageMode>>(modes).selected, {
        LargeMessageMode.unlimited,
      });
      expect(tester.takeException(), isNull);
    });
  }
}
