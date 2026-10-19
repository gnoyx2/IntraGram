import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/features/home/home_screen.dart';
import 'package:intragram/features/portal/portal_sheet.dart';
import 'package:intragram/features/settings/settings_screen.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/vault.dart';
import 'package:intragram/theme/app_theme.dart';

import '_harness.dart';

void main() {
  testWidgets('portal sheet opens from the home app bar', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.wrap(const HomeScreen()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.qr_code_2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PortalSheet), findsOneWidget);
    expect(find.text('Guest portal'), findsOneWidget);
    expect(find.text('Local web server'), findsOneWidget);
  });

  testWidgets('portal sheet shows the QR and URL when the server is up', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(h.store),
          linkRegistryProvider.overrideWithValue(h.registry),
          appIdentityProvider.overrideWithValue(h.identity),
          serverControllerProvider.overrideWith(_RunningServer.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => PortalSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('192.168.1.9:7890'), findsWidgets);
    expect(find.byIcon(Icons.copy), findsOneWidget);
  });

  testWidgets('the read-only portal address is a full-size touch target on '
      'iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final h = Harness();
      addTearDown(h.dispose);
      await tester.pumpWidget(
        h.wrap(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => PortalSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          overrides: [
            serverControllerProvider.overrideWith(_RunningServer.new),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 실제 글꼴(모노스페이스 14)에선 42pt라 iOS 44pt에 모자랐음: 칸 높이를 48로 고정
      final address = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.fontFamily == 'monospace' &&
            (w.data ?? '').contains('192.168.1.9'),
      );
      expect(tester.getSize(address).height, greaterThanOrEqualTo(48));
      // 입장 코드가 든 주소는 고르기 복사(일반 클립보드)로 새지 않음: 복사는 버튼만
      expect(find.byType(SelectableText), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('settings gates the sub-toggles behind the master switch', (
    tester,
  ) async {
    final h = Harness();
    addTearDown(h.dispose);
    final dir = Directory.systemTemp.createTempSync('intragram_ui_vault');
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryStoreProvider.overrideWithValue(h.store),
          linkRegistryProvider.overrideWithValue(h.registry),
          appIdentityProvider.overrideWithValue(h.identity),
          vaultProvider.overrideWithValue(
            Vault(resolveDir: () async => dir.path),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    SwitchListTile messagesTile() => tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Messages'),
    );
    expect(
      messagesTile().onChanged,
      isNull,
      reason: 'disabled while master off',
    );

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Keep chats on this device'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      messagesTile().onChanged,
      isNotNull,
      reason: 'enabled once master on',
    );

    // 보관 범위는 사용자가 정할 수 있음
    await tester.tap(find.widgetWithText(SwitchListTile, 'Messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(messagesTile().value, isFalse);
  });
}

class _RunningServer extends ServerController {
  @override
  ServerState build() => const ServerState(
    running: true,
    host: '192.168.1.9',
    port: 7890,
    // 포털은 opt-in: QR/URL 렌더링 자체를 검사하는 이 테스트는 이미 켜진
    // 상태를 픽스처로 줌(옵트인 스위치 자체는 별도 검사 대상)
    portalEnabled: true,
    portalToken: 'test-token',
  );
}
