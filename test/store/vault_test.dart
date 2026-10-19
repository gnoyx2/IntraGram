import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/vault.dart';

import '../support/vault_snapshot.dart';

void main() {
  late Directory dir;
  late Vault vault;
  const pinned = VaultSettings(enabled: true, pinProtected: true);
  Vault open() => Vault(resolveDir: () async => dir.path);
  Map<String, dynamic> read() =>
      jsonDecode(File('${dir.path}/vault.json').readAsStringSync())
          as Map<String, dynamic>;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vault_session');
    vault = open();
  });
  tearDown(() {
    vault.dispose();
    dir.deleteSync(recursive: true);
  });

  test(
    'setPin and unlock derive once; saves reuse the key and fresh nonces',
    () async {
      vault.setPin('1357');
      await vault.save(snap(settings: pinned));
      expect(vault.debugKdfCount, 1);
      final key = vault.debugSessionKey;
      final first = read();
      for (var i = 0; i < 3; i++) {
        await vault.save(snap(settings: pinned));
        expect(identical(vault.debugSessionKey, key), isTrue);
        expect(read()['n'], isNot(first['n']));
      }
      expect(vault.debugKdfCount, 1);
      vault.lock();
      expect(await vault.unlock('1357'), isNotNull);
      expect(vault.debugKdfCount, 2);
      await vault.save(snap(settings: pinned));
      expect(vault.debugKdfCount, 2);
    },
  );

  test(
    'duress KDF is cached and survives real PIN rotation after restart',
    () async {
      vault.setPin('1357');
      vault.setDecoyPin('2468');
      await vault.save(snap(settings: pinned));
      final before = read();
      expect(before['ds'], isNot((before['kdf'] as Map)['salt']));
      final count = vault.debugKdfCount;
      await vault.save(snap(settings: pinned));
      expect(vault.debugKdfCount, count);
      vault.dispose();
      vault = open();
      await vault.unlock('1357');
      final oldKey = vault.debugSessionKey!;
      expect((oldKey.bytes as SensitiveBytes).overwriteWhenDestroyed, isTrue);
      vault.setPin('9999');
      expect(oldKey.hasBeenDestroyed, isTrue);
      expect(() => oldKey.bytes, throwsStateError);
      await vault.save(snap(settings: pinned));
      final after = read();
      expect(
        (after['kdf'] as Map)['salt'],
        isNot((before['kdf'] as Map)['salt']),
      );
      expect(after['ds'], before['ds']);
      expect(after['dchk'], before['dchk']);
      expect(await vault.isDecoyPin('2468'), isTrue);
      expect(await vault.unlock('1357'), isNull);
      expect(await vault.unlock('9999'), isNotNull);
      expect(await vault.unlock('2468'), isNotNull);
      expect(vault.isDecoyMode, isTrue);
      expect(vault.debugSessionKey, isNull);
    },
  );

  test('removing PIN clears duress state before setting a new PIN', () async {
    vault.setPin('1357');
    vault.setDecoyPin('2468');
    await vault.save(snap(settings: pinned));
    final before = read();
    vault.setPin(null);
    expect(await vault.isDecoyPin('2468'), isFalse);
    vault.setPin('9999');
    await vault.save(snap(settings: pinned));
    expect(read()['dchk'], isNot(before['dchk']));
    expect(read()['ds'], isNot(before['ds']));
    expect(await vault.unlock('2468'), isNull);
    expect(await vault.unlock('9999'), isNotNull);
  });

  for (final action in ['lock', 'erase', 'dispose']) {
    test(
      '$action immediately zeroes cached bytes and rejects protected saves',
      () async {
        vault.setPin('1357');
        await vault.save(snap(settings: pinned));
        final key = vault.debugSessionKey!;
        expect((key.bytes as SensitiveBytes).overwriteWhenDestroyed, isTrue);
        Future<void>? erased;
        switch (action) {
          case 'lock':
            vault.lock();
          case 'erase':
            erased = vault.erase();
          case 'dispose':
            vault.dispose();
        }
        expect(key.hasBeenDestroyed, isTrue);
        expect(() => key.bytes, throwsStateError);
        expect(vault.debugSessionKey, isNull);
        await erased;
        await expectLater(
          vault.save(snap(settings: pinned)),
          throwsA(isA<VaultLockedException>()),
        );
      },
    );
  }

  test('lock during key derivation cannot restore a session key', () async {
    final atPath = Completer<void>();
    final resume = Completer<void>();
    vault.debugStageHook = (stage) async {
      if (stage == 'path') {
        atPath.complete();
        await resume.future;
      }
    };
    vault.setPin('1357');
    final saving = vault.save(snap(settings: pinned));
    await atPath.future;
    vault.lock();
    resume.complete();
    await saving;
    expect(vault.debugSessionKey, isNull);
    expect(File('${dir.path}/vault.json').existsSync(), isFalse);
    // 새 설정의 KDF까지 기다린 뒤에도 이전 결과가 끼어들지 않는지 확인함
    vault.debugStageHook = null;
    vault.setPin('9999');
    await vault.save(snap(settings: pinned));
    expect(await vault.unlock('9999'), isNotNull);
    expect(await vault.unlock('1357'), isNull);
  });
}
