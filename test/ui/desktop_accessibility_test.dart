import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/settings/pin_gate_screen.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/tokens.dart';
import 'package:intragram/widgets/adaptive_dialog_action.dart';

import '_harness.dart';

class _LockedAccess extends VaultAccessNotifier {
  @override
  VaultAccessState build() => const VaultLocked();
}

Future<void> _event(String method, bool value) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'intragram/privacy',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)),
        (_) {},
      );
}

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} live accessibility updates and resets',
      (tester) async {
        final h = Harness();
        addTearDown(h.dispose);
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          OsPrivacy.reduceTransparency.value = false;
          OsPrivacy.reduceMotion.value = false;
          OsPrivacy.highContrast.value = false;
        });
        mockPrivacyChannel([]);
        await tester.pumpWidget(
          h.wrap(
            const IntraGramApp(),
            overrides: [
              vaultAccessProvider.overrideWith(_LockedAccess.new),
              notificationBridgeProvider.overrideWith((ref) {}),
              roomHintBridgeProvider.overrideWith((ref) {}),
              screenshotBridgeProvider.overrideWith((ref) {}),
            ],
          ),
        );
        await tester.pumpAndSettle();
        BuildContext current() => tester.element(find.byType(PinGateScreen));
        expect(isCupertinoDialog(current()), platform == TargetPlatform.macOS);
        for (final method in [
          'onReduceTransparencyChanged',
          'onReduceMotionChanged',
          'onHighContrastChanged',
        ]) {
          await _event(method, true);
          await tester.pumpAndSettle();
          if (method != 'onReduceMotionChanged') {
            final theme = Theme.of(current());
            expect(isCupertinoDialog(current()), isFalse);
            expect(theme.colorScheme.outlineVariant, theme.colorScheme.outline);
            expect(
              theme.colorScheme.onSurfaceVariant,
              theme.colorScheme.onSurface,
            );
            expect(theme.dialogTheme.backgroundColor!.a, 1);
            expect(
              (theme.dialogTheme.shape! as RoundedRectangleBorder).side.width,
              AppBorder.defined,
            );
          }
          if (method == 'onReduceMotionChanged') {
            expect(MediaQuery.disableAnimationsOf(current()), isTrue);
          }
          if (method == 'onHighContrastChanged') {
            expect(MediaQuery.highContrastOf(current()), isTrue);
          }
          await _event(method, false);
          await tester.pumpAndSettle();
        }
        expect(MediaQuery.disableAnimationsOf(current()), isFalse);
        expect(MediaQuery.highContrastOf(current()), isFalse);
        expect(isCupertinoDialog(current()), platform == TargetPlatform.macOS);
        final theme = Theme.of(current());
        expect(
          theme.colorScheme.outlineVariant,
          isNot(theme.colorScheme.outline),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name} starts with settings the OS already has on',
      (tester) async {
        final h = Harness();
        addTearDown(h.dispose);
        addTearDown(_resetAccessibility);
        const channel = MethodChannel('intragram/privacy');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => _keys.contains(call.method) ? true : null,
        );
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(
          h.wrap(
            const IntraGramApp(),
            overrides: [
              vaultAccessProvider.overrideWith(_LockedAccess.new),
              notificationBridgeProvider.overrideWith((ref) {}),
              roomHintBridgeProvider.overrideWith((ref) {}),
              screenshotBridgeProvider.overrideWith((ref) {}),
            ],
          ),
        );
        await tester.pumpAndSettle();
        BuildContext current() => tester.element(find.byType(PinGateScreen));
        final theme = Theme.of(current());
        expect(MediaQuery.disableAnimationsOf(current()), isTrue);
        expect(MediaQuery.highContrastOf(current()), isTrue);
        expect(isCupertinoDialog(current()), isFalse);
        expect(theme.colorScheme.outlineVariant, theme.colorScheme.outline);
        expect(theme.dialogTheme.backgroundColor!.a, 1);
        // OS에서 끄면 그대로 따라옴
        for (final key in _keys) {
          await _event(
            'on${key[0].toUpperCase()}${key.substring(1)}Changed',
            false,
          );
        }
        await tester.pumpAndSettle();
        expect(MediaQuery.disableAnimationsOf(current()), isFalse);
        expect(MediaQuery.highContrastOf(current()), isFalse);
        expect(isCupertinoDialog(current()), platform == TargetPlatform.macOS);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets('pending initial queries cannot overwrite newer OS events', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('intragram/privacy');
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      _resetAccessibility();
    });
    final refresh = OsPrivacy.refreshAccessibility();
    await tester.pump();
    for (final key in _keys) {
      await _event('on${key[0].toUpperCase()}${key.substring(1)}Changed', true);
    }
    pending.complete(false);
    await refresh;
    expect(OsPrivacy.reduceTransparency.value, isTrue);
    expect(OsPrivacy.reduceMotion.value, isTrue);
    expect(OsPrivacy.highContrast.value, isTrue);
  });
}

const _keys = ['reduceTransparency', 'reduceMotion', 'highContrast'];

void _resetAccessibility() {
  OsPrivacy.reduceTransparency.value = false;
  OsPrivacy.reduceMotion.value = false;
  OsPrivacy.highContrast.value = false;
}
