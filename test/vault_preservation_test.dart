import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/store/vault.dart';

import 'support/vault_snapshot.dart';

Future<void> _waitForLocked(ProviderContainer container) async {
  final ready = Completer<void>();
  final subscription = container.listen<VaultAccessState>(vaultAccessProvider, (
    _,
    next,
  ) {
    if (next is VaultLocked && !ready.isCompleted) ready.complete();
  }, fireImmediately: true);
  try {
    await ready.future.timeout(const Duration(seconds: 30));
  } finally {
    subscription.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startFresh cannot replace a locked archive by enabling the vault',
    () async {
      final dir = Directory.systemTemp.createTempSync('intragram_preserve_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final seed = Vault(resolveDir: () async => dir.path)..setPin('1357');
      await seed.save(
        snap(settings: const VaultSettings(enabled: true, pinProtected: true)),
      );
      final file = File('${dir.path}/vault.json');
      final original = file.readAsBytesSync();

      final vault = Vault(resolveDir: () async => dir.path);
      final container = ProviderContainer(
        overrides: [vaultProvider.overrideWithValue(vault)],
      );
      addTearDown(container.dispose);
      final access = container.read(vaultAccessProvider.notifier);
      await _waitForLocked(container);
      expect(container.read(vaultAccessProvider), isA<VaultLocked>());
      access.startFresh();

      final settings = container.read(vaultSettingsProvider.notifier);
      await expectLater(
        settings.setEnabled(true),
        throwsA(isA<VaultLockedException>()),
      );
      expect(container.read(vaultSettingsProvider).enabled, isFalse);
      await settings.setLangOverride('ko'); // RAM 전용 설정은 계속 쓸 수 있음
      expect(file.readAsBytesSync(), original);
    },
  );

  test('a malformed existing archive stays behind the PIN gate', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_corrupt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/vault.json').writeAsStringSync('{invalid');
    final vault = Vault(resolveDir: () async => dir.path);
    expect(await vault.isEncrypted(), isTrue);
  });

  test('startFresh never writes or deletes the old identity file', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_identity_gate_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final seed = Vault(resolveDir: () async => dir.path)..setPin('1357');
    await seed.save(
      snap(settings: const VaultSettings(enabled: true, pinProtected: true)),
    );
    final identityFile = File('${dir.path}/identity.json')
      ..writeAsStringSync('{"alias":"real-user"}');
    final original = identityFile.readAsBytesSync();
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(
          Vault(resolveDir: () async => dir.path),
        ),
        identityStoreProvider.overrideWithValue(
          IdentityStore(resolveDir: () async => dir.path),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(vaultAccessProvider);
    await _waitForLocked(container);
    container.read(vaultAccessProvider.notifier).startFresh();

    final alias = container.read(identityAliasProvider.notifier);
    await alias.rename('fresh-name', save: true);
    await alias.resetToRandom();
    expect(identityFile.readAsBytesSync(), original);
  });

  test('panic still erases an archive preserved by startFresh', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_panic_vault_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final seed = Vault(resolveDir: () async => dir.path)..setPin('1357');
    await seed.save(
      snap(settings: const VaultSettings(enabled: true, pinProtected: true)),
    );
    final file = File('${dir.path}/vault.json');
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(
          Vault(resolveDir: () async => dir.path),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(vaultAccessProvider);
    await _waitForLocked(container);
    container.read(vaultAccessProvider.notifier).startFresh();
    await container.read(vaultSettingsProvider.notifier).eraseForPanic();
    expect(file.existsSync(), isFalse);
  });
}
