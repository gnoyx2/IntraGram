import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/app_providers.dart';
import 'package:intragram/core/identity_store.dart';
import 'package:intragram/features/home/panic_sequence.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/vault.dart';

import '../../support/panic_fakes.dart';
import '../../support/test_identities.dart';
import '../../support/vault_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('duress panic erases every file and replaces the key', () async {
    final dir = Directory.systemTemp.createTempSync('duress_panic_');
    final vault = Vault(resolveDir: () async => dir.path);
    final identityStore = IdentityStore(resolveDir: () async => dir.path);
    final store = InMemoryStore();
    final steps = PanicSteps()..completeAll();
    final container = ProviderContainer(
      overrides: [
        vaultProvider.overrideWithValue(vault),
        serverControllerProvider.overrideWith(() => PanicServer(steps)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      store.dispose();
      await store.drainDisposals();
      dir.deleteSync(recursive: true);
    });
    vault.setPin('real123');
    vault.setDecoyPin('decoy123');
    await vault.save(
      snap(settings: const VaultSettings(enabled: true, pinProtected: true)),
    );
    await identityStore.saveAlias('private alias');
    container.read(vaultAccessProvider);
    await pumpEventQueue();
    expect(
      await container.read(vaultAccessProvider.notifier).unlock('decoy123'),
      isTrue,
    );
    expect(vault.isDecoyMode, isTrue);
    for (final name in ['vault.json', 'identity.json']) {
      expect(File('${dir.path}/$name').existsSync(), isTrue);
      File('${dir.path}/$name.tmp').writeAsStringSync('pending');
    }
    final settings = File('${dir.path}/download_directories.json')
      ..writeAsStringSync('["/private/folder"]');
    File('${settings.path}.tmp').writeAsStringSync('pending');
    final identity = testIdentity('a');
    final oldPeerId = identity.peerId;
    final result = await executePanicWipe(
      sweepTemp: () async {},
      store: store,
      registry: PanicRegistry(steps, store: store),
      serverController: container.read(serverControllerProvider.notifier),
      foregroundService: PanicForeground(steps),
      notificationService: PanicNotifications(steps),
      vaultSettings: container.read(vaultSettingsProvider.notifier),
      vaultAccess: container.read(vaultAccessProvider.notifier),
      identityStore: identityStore,
      identity: identity,
      directorySettingsFile: File('${dir.path}/download_directories.json'),
      clearClipboard: () async {},
      releaseNativeSources: () async {},
    );
    expect(result.isComplete, isTrue, reason: '${result.failures}');
    expect(dir.listSync(), isEmpty);
    expect(identity.peerId, isNot(oldPeerId));
  });
}
