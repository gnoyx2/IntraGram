import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/chat/message_bubble.dart';
import 'package:intragram/features/settings/pin_gate_screen.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/theme/app_theme.dart';
import 'package:intragram/theme/tokens.dart';

import '../support/contrast.dart';
import '_harness.dart';

class _LockedAccess extends VaultAccessNotifier {
  @override
  VaultAccessState build() => const VaultLocked();
}

void main() {
  for (final dark in [false, true]) {
    test('${dark ? 'dark' : 'light'} transparency fallback preserves AAA', () {
      ThemeData make({bool reduced = false, bool contrast = false}) => dark
          ? AppTheme.dark(highContrast: contrast, reduceTransparency: reduced)
          : AppTheme.light(highContrast: contrast, reduceTransparency: reduced);
      final baseline = make();
      // 투명도 줄이기와 대비 높이기를 같이 켜도 한쪽이 빠지지 않음
      for (final theme in [
        make(reduced: true),
        make(contrast: true),
        make(reduced: true, contrast: true),
      ]) {
        final scheme = theme.colorScheme;
        final chat = theme.extension<ChatColors>()!;
        expect(scheme.surface, baseline.colorScheme.surface);
        expect(scheme.onSurfaceVariant, scheme.onSurface);
        expect(scheme.outlineVariant, scheme.outline);
        expect(chat.bubbleMine, baseline.extension<ChatColors>()!.bubbleMine);
        expect(chat.bubbleMineEdge, scheme.outline);
        expect(
          contrastRatio(chat.onBubbleMine, chat.bubbleMine),
          greaterThan(7),
        );
        expect(
          contrastRatio(chat.onBubbleTheirs, chat.bubbleTheirs),
          greaterThan(7),
        );
        expect(
          contrastRatio(chat.bubbleMineEdge, chat.canvas),
          greaterThan(1.25),
        );
        final shape = theme.dialogTheme.shape! as RoundedRectangleBorder;
        expect(shape.side.width, AppBorder.defined);
        expect(shape.side.color, scheme.outline);
        expect(
          theme.inputDecorationTheme.enabledBorder!.borderSide.width,
          AppBorder.defined,
        );
        expect(
          (theme.appBarTheme.shape! as Border).bottom.width,
          AppBorder.defined,
        );
        expect(theme.bottomSheetTheme.backgroundColor!.a, 1);
        expect(
          bubbleDecoration(
            chat: chat,
            scheme: scheme,
            mine: true,
            joinsPrevious: false,
            joinsNext: false,
          ),
          isA<ShapeDecoration>(),
        );
      }
    });
  }

  testWidgets('system transparency changes update mounted app surfaces', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    OsPrivacy.reduceTransparency.value = false;
    addTearDown(() => OsPrivacy.reduceTransparency.value = false);
    mockPrivacyChannel([]);
    await tester.pumpWidget(
      h.wrap(
        const IntragramApp(),
        overrides: [
          vaultAccessProvider.overrideWith(_LockedAccess.new),
          notificationBridgeProvider.overrideWith((ref) {}),
          roomHintBridgeProvider.overrideWith((ref) {}),
          screenshotBridgeProvider.overrideWith((ref) {}),
        ],
      ),
    );
    await tester.pump();
    ThemeData current() => Theme.of(tester.element(find.byType(PinGateScreen)));
    expect(
      current().colorScheme.outlineVariant,
      isNot(current().colorScheme.outline),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'intragram/privacy',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onReduceTransparencyChanged', true),
          ),
          (_) {},
        );
    await tester.pumpAndSettle();
    expect(current().colorScheme.outlineVariant, current().colorScheme.outline);
    expect(
      (current().dialogTheme.shape! as RoundedRectangleBorder).side.width,
      AppBorder.defined,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    OsPrivacy.reduceTransparency.value = false;
  });
}
