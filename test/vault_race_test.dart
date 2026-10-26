import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/store/vault.dart';

import 'support/vault_snapshot.dart';

// PBKDF2-HMAC-SHA256 + ChaCha20-Poly1305로 Vault와 같은 봉인 파일 형식을 직접 조립함:
// 구버전 100k나 비정상 iter 값을 넣어 시험해야 하므로 항상 현재 kVaultPbkdf2Iterations로만
// 봉인하는 Vault.save 경로를 그대로 쓸 수 없음
Future<String> _sealManually(
  String plaintext,
  String pin,
  List<int> salt, {
  required int iterations,
  String? dchk,
}) async {
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: pin, nonce: salt);
  final aead = Chacha20.poly1305Aead();
  final box = await aead.encrypt(
    utf8.encode(plaintext),
    secretKey: key,
    nonce: aead.newNonce(),
  );
  return jsonEncode(<String, dynamic>{
    'v': 1,
    'enc': true,
    'kdf': <String, dynamic>{'salt': base64.encode(salt), 'iter': iterations},
    'n': base64.encode(box.nonce),
    'c': base64.encode(box.cipherText),
    'm': base64.encode(box.mac.bytes),
    'dchk': dchk ?? base64.encode(List<int>.filled(32, 7)),
  });
}

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_vault_race');
    file = File('${dir.path}/vault.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('kdf.iter compatibility', () {
    const pin = '1357';
    final salt = List<int>.generate(16, (i) => i);
    const pinned = VaultSettings(enabled: true, pinProtected: true);
    final plaintext = jsonEncode(snap(settings: pinned).toJson());

    test('a legacy 100k vault opens and is rewritten at 200k', () async {
      file.writeAsStringSync(
        await _sealManually(
          plaintext,
          pin,
          salt,
          iterations: kVaultLegacyPbkdf2Iterations,
        ),
      );
      final vault = Vault(resolveDir: () async => dir.path);
      final loaded = await vault.unlock(pin);
      expect(loaded?.messages.single.text, 'hello');
      expect(vault.needsRewrite, isTrue);
      await vault.save(loaded!);
      expect(vault.needsRewrite, isFalse);
      expect(
        (jsonDecode(file.readAsStringSync())['kdf'] as Map)['iter'],
        kVaultPbkdf2Iterations,
      );
      expect(
        await Vault(resolveDir: () async => dir.path).unlock(pin),
        isNotNull,
      );
    });

    test('legacy duress PIN still works after the 200k rewrite', () async {
      final duressKey = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: kVaultLegacyPbkdf2Iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: '2468', nonce: salt);
      file.writeAsStringSync(
        await _sealManually(
          plaintext,
          pin,
          salt,
          iterations: kVaultLegacyPbkdf2Iterations,
          dchk: base64.encode(await duressKey.extractBytes()),
        ),
      );
      final vault = Vault(resolveDir: () async => dir.path);
      final loaded = await vault.unlock(pin);
      expect(await vault.isDecoyPin('2468'), isTrue);
      await vault.save(loaded!);
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(saved['di'], kVaultLegacyPbkdf2Iterations);
      final decoy = Vault(resolveDir: () async => dir.path);
      expect(await decoy.unlock('2468'), isNotNull);
      expect(decoy.isDecoyMode, isTrue);
    });

    test('a missing kdf.iter is rejected, not silently defaulted', () async {
      final sealed =
          jsonDecode(
                await _sealManually(plaintext, pin, salt, iterations: 100000),
              )
              as Map<String, dynamic>;
      (sealed['kdf'] as Map<String, dynamic>).remove('iter');
      file.writeAsStringSync(jsonEncode(sealed));

      final vault = Vault(resolveDir: () async => dir.path);
      expect(await vault.unlock(pin), isNull);
    });

    test(
      'an unsupported kdf.iter (e.g. attacker-lowered) is rejected',
      () async {
        file.writeAsStringSync(
          await _sealManually(plaintext, pin, salt, iterations: 1),
        );
        final vault = Vault(resolveDir: () async => dir.path);
        expect(await vault.unlock(pin), isNull);
      },
    );

    test('a negative kdf.iter is rejected', () async {
      final sealed =
          jsonDecode(
                await _sealManually(plaintext, pin, salt, iterations: 100000),
              )
              as Map<String, dynamic>;
      (sealed['kdf'] as Map<String, dynamic>)['iter'] = -1;
      file.writeAsStringSync(jsonEncode(sealed));

      final vault = Vault(resolveDir: () async => dir.path);
      expect(await vault.unlock(pin), isNull);
    });
  });

  group('save() refuses to fall back to plaintext', () {
    test(
      'pinProtected with no session PIN throws instead of writing plaintext',
      () async {
        final vault = Vault(resolveDir: () async => dir.path);
        await expectLater(
          vault.save(
            snap(
              settings: const VaultSettings(enabled: true, pinProtected: true),
            ),
          ),
          throwsA(isA<VaultLockedException>()),
        );
        expect(file.existsSync(), isFalse);
      },
    );

    test('enabled: false is a no-op — no file is created', () async {
      final vault = Vault(resolveDir: () async => dir.path);
      await vault.save(snap(settings: const VaultSettings(enabled: false)));
      expect(file.existsSync(), isFalse);
    });
  });

  test('duress erase deletes the real vault and pending file', () async {
    final vault = Vault(resolveDir: () async => dir.path);
    vault.setPin('1357');
    vault.setDecoyPin('2468');
    const pinned = VaultSettings(enabled: true, pinProtected: true);
    await vault.save(snap(settings: pinned));
    await vault.unlock('2468');
    expect(vault.isDecoyMode, isTrue);
    final tmp = File('${file.path}.tmp')..writeAsStringSync('pending');
    await vault.erase();
    expect(file.existsSync(), isFalse);
    expect(tmp.existsSync(), isFalse);
    expect(vault.isDecoyMode, isTrue);
    await vault.save(snap(settings: pinned));
    expect(file.existsSync(), isFalse);
  });

  group('save/erase ordering', () {
    test(
      'erase started after a slow save still wins — file ends up gone',
      () async {
        final vault = Vault(resolveDir: () async => dir.path);
        vault.setPin('1357');
        const pinned = VaultSettings(enabled: true, pinProtected: true);

        // 두 호출을 겹쳐서 검: await 없이 save 시작 직후 바로 erase
        final saveFuture = vault.save(snap(settings: pinned));
        final eraseFuture = vault.erase();
        await Future.wait([saveFuture, eraseFuture]);

        expect(
          file.existsSync(),
          isFalse,
          reason: 'erase queued after save must be the final word',
        );
      },
    );

    test(
      'several saves queued before an erase all lose to that erase',
      () async {
        final vault = Vault(resolveDir: () async => dir.path);
        const plain = VaultSettings(enabled: true);
        // 셋 다 erase보다 먼저 큐에 걸림: 전부 그 시점의(erase 전) epoch를
        // 붙잡고 있어서, erase가 훑고 지나가면 전부 스킵돼야 함
        final saves = [
          vault.save(snap(settings: plain)),
          vault.save(snap(settings: plain)),
          vault.save(snap(settings: plain)),
        ];
        final eraseFuture = vault.erase();
        await Future.wait([...saves, eraseFuture]);

        expect(
          file.existsSync(),
          isFalse,
          reason: 'none of the pre-erase saves may resurrect the file',
        );
      },
    );
  });
}
