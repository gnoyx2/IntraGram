import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/features/home/widgets/discovery_radar.dart';
import 'package:intragram/features/home/widgets/home_sections.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/discovery_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import '../support/portal_guest.dart' show identity;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const privacy = MethodChannel('intragram/privacy');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    OsPrivacy.reduceTransparency.value = false;
    messenger.setMockMethodCallHandler(privacy, null);
  });

  test(
    'system transparency query and notification update the cached value',
    () async {
      messenger.setMockMethodCallHandler(privacy, (call) async {
        expect(call.method, 'reduceTransparency');
        return true;
      });
      await OsPrivacy.refreshReduceTransparency();
      expect(OsPrivacy.reduceTransparency.value, isTrue);
      await messenger.handlePlatformMessage(
        privacy.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onReduceTransparencyChanged', false),
        ),
        (_) {},
      );
      expect(OsPrivacy.reduceTransparency.value, isFalse);
    },
  );

  testWidgets('denied LAN access blocks server start and offers app settings', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(privacy, (call) async {
      calls.add(call.method);
      return call.method == 'openAppSettings';
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(serverControllerProvider.notifier).start();
    final server = container.read(serverControllerProvider);
    expect(server.running, isFalse);
    expect(server.problem, ServerProblem.localNetworkDenied);
    expect(calls, ['requestLocalNetworkPermission']);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ErrorBanner(server: server)),
      ),
    );
    const en = S(AppLang.en);
    expect(find.text(en.t('server.localNetworkDeniedTitle')), findsOneWidget);
    expect(find.text(en.t('server.localNetworkDenied')), findsOneWidget);
    await tester.tap(find.text(en.t('settings.open')));
    await tester.pump();
    expect(calls.last, 'openAppSettings');

    await container.read(serverControllerProvider.notifier).start();
    expect(calls.last, 'checkLocalNetworkPermission');
    expect(container.read(serverControllerProvider).running, isFalse);
  });

  // 처음엔 거부, 설정에서 켠 뒤 복귀 점검(refreshNetwork)
  Future<void> deniedThenGranted() async {
    var granted = false;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(privacy, (call) async {
      calls.add(call.method);
      return granted;
    });
    final store = InMemoryStore();
    final registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
    );
    final container = ProviderContainer(
      overrides: [
        linkRegistryProvider.overrideWithValue(registry),
        appIdentityProvider.overrideWithValue(identity()),
        discoveryControllerProvider.overrideWith(_IdleDiscovery.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await registry.disposeAll();
      store.dispose();
    });
    final server = container.read(serverControllerProvider.notifier);
    await server.start();
    expect(
      container.read(serverControllerProvider).problem,
      ServerProblem.localNetworkDenied,
    );

    granted = true;
    await server.refreshNetwork();
    expect(calls.last, 'checkLocalNetworkPermission');
    expect(
      container.read(serverControllerProvider).problem,
      isNot(ServerProblem.localNetworkDenied),
    );
    await server.stop();
  }

  // 설정에서 권한을 켜고 앱으로 돌아오면(resumed의 refreshNetwork) 재시작 없이 거부 상태를 벗어남.
  // 망이 있으면 서버·탐색이 다시 뜨고, 없으면 거부 안내가 '망 없음'으로 바뀜 (이 기기의 실제 망에 따라 둘 중 하나)
  for (final offline in [false, true]) {
    test('granting LAN access in Settings recovers on resume '
        '(offline: $offline)', () async {
      if (offline) {
        final real = ServerController.bindAddress;
        ServerController.bindAddress = () async => null;
        addTearDown(() => ServerController.bindAddress = real);
      }
      await deniedThenGranted();
    });
  }

  testWidgets('the radar names a denied LAN permission and opens Settings', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(privacy, (call) async {
      calls.add(call.method);
      return true;
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiscoveryRadar(reason: DiscoveryEmptyReason.localNetworkDenied),
        ),
      ),
    );
    const en = S(AppLang.en);
    expect(find.text(en.t('server.localNetworkDeniedTitle')), findsOneWidget);
    expect(find.text(en.t('home.noWifi')), findsNothing);
    await tester.tap(find.text(en.t('settings.open')));
    await tester.pump();
    expect(calls, ['openAppSettings']);
  });

  test('iOS privacy covers every scene window and keeps idiom detection', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(source, contains('UIAccessibility.isReduceTransparencyEnabled'));
    expect(source, contains('reduceTransparencyStatusDidChangeNotification'));
    expect(source, contains('for window in scene.windows'));
    expect(
      source,
      contains('cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]'),
    );
    expect(source, contains('cover.frame = window.bounds'));
    expect(source, contains('UIDevice.current.userInterfaceIdiom == .pad'));
    expect(source, isNot(contains(r'first { $0.isKeyWindow }')));
    expect(source, isNot(contains('CoreSpotlight')));
    expect(source, isNot(contains('NSUserActivity(')));
    final identity = File('lib/core/app_identity.dart').readAsStringSync();
    expect(identity, contains('OsPrivacy.cachedIsPad'));
    expect(identity, isNot(contains('shortestSide')));
  });
}

class _IdleDiscovery extends DiscoveryController {
  @override
  List<PeerDevice> build() => const <PeerDevice>[];

  @override
  Future<void> start({
    required AppIdentity identity,
    required int port,
  }) async {}

  @override
  Future<void> stop() async {}
}
