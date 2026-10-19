import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/vault.dart';

import 'support/vault_snapshot.dart';

void main() {
  late Directory dir;
  late Vault vault;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_vault');
    vault = Vault(resolveDir: () async => dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('PIN-protected vault', () {
    const pinned = VaultSettings(enabled: true, pinProtected: true);

    test('pinProtected defaults off and round-trips through json', () {
      expect(const VaultSettings().pinProtected, isFalse);
      expect(VaultSettings.fromJson(pinned.toJson()).pinProtected, isTrue);
      expect(
        VaultSettings.fromJson(const <String, dynamic>{}).pinProtected,
        isFalse,
      );
    });

    test('a session PIN seals the file — no plaintext leaks', () async {
      vault.setPin('1357');
      await vault.save(snap(settings: pinned));

      final raw =
          jsonDecode(File('${dir.path}/vault.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(raw['enc'], isTrue);
      expect(raw.containsKey('messages'), isFalse);
      expect(
        File('${dir.path}/vault.json').readAsStringSync().contains('hello'),
        isFalse,
      );
    });

    test('a fresh Vault sees a locked file and cannot plain-load it', () async {
      vault.setPin('1357');
      await vault.save(snap(settings: pinned));

      final fresh = Vault(resolveDir: () async => dir.path);
      expect(await fresh.isEncrypted(), isTrue);
      expect(await fresh.load(), isNull);
    });

    test('unlock with the right PIN round-trips the snapshot', () async {
      vault.setPin('1357');
      await vault.save(snap(settings: pinned));

      final fresh = Vault(resolveDir: () async => dir.path);
      final loaded = await fresh.unlock('1357');
      expect(loaded, isNotNull);
      expect(loaded!.messages.single.text, 'hello');
      expect(loaded.settings.pinProtected, isTrue);
    });

    test(
      'a wrong PIN returns null and leaves the file byte-identical',
      () async {
        vault.setPin('1357');
        await vault.save(snap(settings: pinned));
        final before = File('${dir.path}/vault.json').readAsStringSync();

        final fresh = Vault(resolveDir: () async => dir.path);
        expect(await fresh.unlock('9999'), isNull);
        expect(File('${dir.path}/vault.json').readAsStringSync(), before);
      },
    );

    test('removing the PIN writes the file back as plain JSON', () async {
      vault.setPin('1357');
      await vault.save(snap(settings: pinned));

      vault.setPin(null);
      await vault.save(snap(settings: const VaultSettings(enabled: true)));
      final loaded = await vault.load();
      expect(loaded, isNotNull);
      expect(loaded!.messages.single.text, 'hello');
    });
  });

  group('duress (decoy) PIN', () {
    const pinned = VaultSettings(enabled: true, pinProtected: true);

    test('dchk is present even when no duress PIN is set', () async {
      vault.setPin('1357');
      await vault.save(snap(settings: pinned));

      final raw =
          jsonDecode(File('${dir.path}/vault.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(raw['dchk'], isA<String>());
    });

    test(
      'the duress PIN opens an empty session that never touches disk',
      () async {
        vault.setPin('1357');
        expect(vault.setDecoyPin('2468'), isTrue);
        await vault.save(snap(settings: pinned));
        final onDisk = File('${dir.path}/vault.json').readAsStringSync();

        final fresh = Vault(resolveDir: () async => dir.path);
        final decoy = await fresh.unlock('2468');
        expect(decoy, isNotNull);
        expect(decoy!.conversations, isEmpty);
        expect(decoy.messages, isEmpty);
        expect(decoy.settings.enabled, isTrue);
        expect(fresh.isDecoyMode, isTrue);

        await fresh.save(snap(settings: pinned));
        expect(File('${dir.path}/vault.json').readAsStringSync(), onDisk);
      },
    );

    test('the real PIN still opens the real archive', () async {
      vault.setPin('1357');
      vault.setDecoyPin('2468');
      await vault.save(snap(settings: pinned));

      final fresh = Vault(resolveDir: () async => dir.path);
      final real = await fresh.unlock('1357');
      expect(real, isNotNull);
      expect(real!.messages.single.text, 'hello');
      expect(fresh.isDecoyMode, isFalse);
    });

    test('a wrong PIN that is not the decoy still returns null', () async {
      vault.setPin('1357');
      vault.setDecoyPin('2468');
      await vault.save(snap(settings: pinned));

      final fresh = Vault(resolveDir: () async => dir.path);
      expect(await fresh.unlock('9999'), isNull);
      expect(fresh.isDecoyMode, isFalse);
    });

    test('setDecoyPin rejects a PIN equal to the real one', () {
      vault.setPin('1357');
      expect(vault.setDecoyPin('1357'), isFalse);
      expect(vault.setDecoyPin('2468'), isTrue);
    });
  });
}
