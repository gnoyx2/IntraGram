import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/foreground_service.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/models.dart';
import 'package:intragram/store/vault.dart';

import 'support/panic_fakes.dart';
import 'support/vault_snapshot.dart';

// 백그라운드 자동 재잠금: 최신 상태를 봉인한 뒤 세션 키를 버리고 RAM을 비워 PIN 게이트로 돌아감
// 같은 PIN으로 다시 열면 봉인한 내용이 하이드레이트됨

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('relock wipes the key after save or timeout', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_relock_');
    final vault = Vault(resolveDir: () async => dir.path);
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(vault),
        serverControllerProvider.overrideWith(
          () => PanicServer(PanicSteps()..completeAll()),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      dir.deleteSync(recursive: true);
    });
    vault.setPin('pin1234');
    await vault.save(
      snap(settings: const VaultSettings(enabled: true, pinProtected: true)),
    );
    // 앱처럼 게이트가 열리기 전부터 설정 provider를 살려 둠 (localeController가 watch함)
    container
      ..read(vaultSettingsProvider)
      ..read(vaultAccessProvider);
    await pumpEventQueue();
    final access = container.read(vaultAccessProvider.notifier);
    expect(await access.unlock('pin1234'), isTrue);

    final store = container.read(inMemoryStoreProvider);
    store.addMessage(
      EphemeralMessage(
        id: 'late',
        conversationId: 'c1',
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: 'me',
        createdAt: DateTime.now(),
        text: 'written after unlock',
        delivery: DeliveryState.delivered,
      ),
    );

    await relockSession(
      store: store,
      registry: LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: AppIdentity(peerId: '1' * 32, alias: 'me', platform: 'x'),
      ),
      serverController: container.read(serverControllerProvider.notifier),
      foregroundService: ForegroundService(isAndroid: false),
      vaultAccess: access,
      settings: container.read(vaultSettingsProvider),
      releaseNativeSources: () async {},
    );

    expect(container.read(vaultAccessProvider), isA<VaultLocked>());
    expect(vault.debugSessionKey, isNull, reason: 'the key left RAM');
    expect(access.canWriteArchive, isFalse);
    expect(store.messageById('late'), isNull, reason: 'RAM was wiped');

    expect(await access.unlock('pin1234'), isTrue);
    expect(store.messageById('late')?.text, 'written after unlock');

    final key = vault.debugSessionKey!;
    final entered = Completer<void>();
    final resume = Completer<void>();
    vault.debugStageHook = (stage) async {
      if (stage == 'path') {
        entered.complete();
        await resume.future;
      }
    };
    final stalledRelock = relockSession(
      store: store,
      registry: LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: AppIdentity(peerId: '1' * 32, alias: 'me', platform: 'x'),
      ),
      serverController: container.read(serverControllerProvider.notifier),
      foregroundService: ForegroundService(isAndroid: false),
      vaultAccess: access,
      settings: container.read(vaultSettingsProvider),
      releaseNativeSources: () async {},
    );
    await entered.future;
    await expectLater(stalledRelock, throwsA(isA<TimeoutException>()));
    expect(key.hasBeenDestroyed, isTrue);
    expect(vault.debugSessionKey, isNull);
    expect(container.read(vaultAccessProvider), isA<VaultLocked>());
    resume.complete();
    vault.debugStageHook = null;
    expect(await access.unlock('pin1234'), isTrue);
    expect(vault.debugSessionKey, isNotNull);
  });

  test('wrong PINs wait 1, 2, 4 ... seconds, at most a minute', () {
    expect(
      [for (var i = 0; i < 8; i++) pinRetryDelay(i).inSeconds],
      [1, 2, 4, 8, 16, 32, 60, 60],
    );
  });
}
