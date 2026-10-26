import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/store/vault.dart';

import 'support/chmod_injection.dart';
import 'support/vault_order_rig.dart';
import 'support/vault_snapshot.dart';

// 진행 중이던 전이를 erase가 무효화해도 이후 저장이 영원히 거부되지 않고, 늦게 끝난 옛 판독이 세션 상태를 못 바꾸며,
// 저장/삭제 실패는 호출자에게 보이고 임시 파일이 안 남고, decoy 세션은 디스크를 안
// 건드림 (저장 단계별 끼어들기/큐 순서는 vault_io_ordering_test.dart)
void main() {
  final r = VaultOrderRig();
  setUp(r.setUp);
  tearDown(r.tearDown);

  // 처음 count번의 resolveDir 호출을 게이트로 잡아 두는 vault
  ({Vault vault, List<Completer<void>> entered, List<Completer<void>> gates})
  gated(int count) {
    final gates = [for (var i = 0; i < count; i++) Completer<void>()];
    final entered = [for (var i = 0; i < count; i++) Completer<void>()];
    var call = 0;
    final vault = Vault(
      resolveDir: () async {
        final i = call++;
        if (i < count) {
          entered[i].complete();
          await gates[i].future;
        }
        return r.dir.path;
      },
    );
    return (vault: vault, entered: entered, gates: gates);
  }

  test('an erase during a load does not leave saves rejected forever, and '
      'the stale load changes no session state', () async {
    await r.openReal();
    final g = gated(1);
    final unlocking = g.vault.unlock(vaultRealPin);
    await g.entered[0].future;

    final erasing = g.vault.erase(); // 진행 중이던 전이를 무효화함
    g.gates[0].complete();
    expect(await unlocking, isNull, reason: 'a stale load is discarded');
    await erasing;

    g.vault.setPin(vaultRealPin);
    await r.saveProtected(g.vault); // "전이 중"으로 거부되면 안 됨
    expect(r.file.existsSync(), isTrue);
    expect(g.vault.isDecoyMode, isFalse);
  });

  for (final stage in ['decrypted', 'decoy-checked']) {
    test('an erase injected at the load stage "$stage" discards the load and '
        'sets no PIN or decoy state', () async {
      await r.openReal();
      final vault = r.vault();
      Future<void>? erasing;
      vault.debugStageHook = (s) async {
        if (s == stage && erasing == null) erasing = vault.erase();
      };
      // 'decrypted'는 진짜 PIN, 'decoy-checked'는 duress PIN 경로
      final pin = stage == 'decrypted' ? vaultRealPin : vaultDuressPin;

      final loaded = await vault.unlock(pin);
      await erasing;

      expect(loaded, isNull, reason: 'the load lost to the erase');
      expect(vault.isDecoyMode, isFalse, reason: 'no decoy state applied');
      await expectLater(
        r.saveProtected(vault),
        throwsA(isA<VaultLockedException>()),
        reason: 'no session PIN was adopted from the stale load',
      );
    });
  }

  test(
    'a stale transition does not lower a newer transition\'s flag',
    () async {
      await r.openReal();
      final g = gated(2);
      final first = g.vault.unlock(vaultRealPin);
      await g.entered[0].future;
      final second = g.vault.unlock('wrong-pin'); // 더 새 전이
      g.gates[0].complete(); // 옛 전이가 먼저 끝남
      expect(await first, isNull, reason: 'superseded by the newer transition');

      // PIN은 있으니 거부 사유는 오직 "전이 중" 하나: 옛 전이가 flag를 내렸다면 통과함
      g.vault.setPin(vaultRealPin);
      await expectLater(
        r.saveProtected(g.vault),
        throwsA(
          isA<VaultLockedException>().having(
            (e) => e.message,
            'message',
            contains('transitioning'),
          ),
        ),
      );

      await g.entered[1].future;
      g.gates[1].complete();
      expect(await second, isNull, reason: 'wrong PIN');
      await r.saveProtected(g.vault); // 새 전이가 끝나자 다시 허용됨
    },
  );

  group('failures are visible and leave no temp file', () {
    test('a disk read error during load reaches the caller', () async {
      r.file.writeAsStringSync('{}');
      Process.runSync('chmod', ['000', r.file.path]);
      await expectLater(r.vault().load(), throwsA(isA<FileSystemException>()));
    }, skip: chmodInjectionSkip);

    test('a failed rename surfaces and cleans its own temp', () async {
      // 아카이브 자리에 디렉터리가 있어서 rename이 실패함
      Directory('${r.dir.path}/vault.json').createSync();

      await expectLater(
        r.vault().save(snap(settings: const VaultSettings(enabled: true))),
        throwsA(isA<FileSystemException>()),
      );

      expect(r.noTmp(), isTrue, reason: 'the writer removes what it created');
    });

    test(
      'a save into an unwritable folder is reported, not swallowed',
      () async {
        Process.runSync('chmod', ['555', r.dir.path]);
        final vault = Vault(resolveDir: () async => '${r.dir.path}/sub');

        await expectLater(
          vault.save(snap(settings: const VaultSettings(enabled: true))),
          throwsA(isA<FileSystemException>()),
        );
      },
      skip: chmodInjectionSkip,
    );

    test(
      'an erase that cannot delete the archive is reported',
      () async {
        final vault = await r.openReal();
        Process.runSync('chmod', ['555', r.dir.path]);

        await expectLater(vault.erase(), throwsA(isA<VaultIoException>()));

        expect(
          r.file.existsSync(),
          isTrue,
          reason: 'still there — and we know',
        );
      },
      skip: chmodInjectionSkip,
    );

    test('erasing an already-missing archive is fine (not-found)', () async {
      await r.vault().erase();

      expect(r.file.existsSync(), isFalse);
    });
  });

  test('decoy saves preserve the archive but erase deletes it', () async {
    final vault = await r.openReal();
    final before = r.file.readAsBytesSync();
    final modified = r.file.lastModifiedSync();
    expect(await vault.unlock(vaultDuressPin), isNotNull);

    await r.saveProtected(vault);

    expect(vault.isDecoyMode, isTrue);
    expect(r.file.readAsBytesSync(), before);
    expect(r.file.lastModifiedSync(), modified);
    expect(r.noTmp(), isTrue);
    await vault.erase();
    expect(r.file.existsSync(), isFalse);
    expect(r.noTmp(), isTrue);
  });
}
