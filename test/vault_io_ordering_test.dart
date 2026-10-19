import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/store/vault.dart';

import 'support/vault_order_rig.dart';

// vault 세션 전이(duress unlock)/erase가 저장과 같은 큐에서
// 직렬화되고, 저장 각 단계(경로 조회, 봉인, 임시 파일 쓰기)에 끼어들어도
// 아카이브가 안 바뀌고 임시 파일이 안 남음 (실패 가시성/전이 flag는 vault_io_failures_test.dart)
void main() {
  final r = VaultOrderRig();
  setUp(r.setUp);
  tearDown(r.tearDown);

  for (final stage in ['path', 'sealed', 'tmp']) {
    test('a duress unlock injected at the "$stage" stage of a save leaves '
        'the real archive untouched', () async {
      final vault = await r.openReal();
      final before = r.file.readAsBytesSync();
      final modified = r.file.lastModifiedSync();
      Future<Object?>? unlocking;
      vault.debugStageHook = (s) async {
        if (s == stage && unlocking == null) {
          // 전이 시작: 판독은 큐에서 저장 뒤에 섬
          unlocking = vault.unlock(vaultDuressPin);
        }
      };

      await r.saveProtected(vault);
      expect(await unlocking, isNotNull);

      expect(vault.isDecoyMode, isTrue);
      expect(r.file.readAsBytesSync(), before);
      expect(r.file.lastModifiedSync(), modified);
      expect(
        r.noTmp(),
        isTrue,
        reason: 'the aborted save cleaned its own temp',
      );
    });

    test('an erase injected at the "$stage" stage of a save wins: no '
        'archive and no temp file are left', () async {
      final vault = await r.openReal();
      Future<void>? erasing;
      vault.debugStageHook = (s) async {
        if (s == stage && erasing == null) erasing = vault.erase();
      };

      await r.saveProtected(vault);
      await erasing;

      expect(
        r.file.existsSync(),
        isFalse,
        reason: 'the save must not resurrect',
      );
      expect(r.noTmp(), isTrue);
    });
  }

  test('a duress unlock waits behind an in-flight save instead of racing it, '
      'and that save can no longer commit', () async {
    await r.openReal();
    final before = r.file.readAsBytesSync();
    var block = false;
    var resolves = 0;
    final entered = Completer<void>();
    final resume = Completer<void>();
    final vault = Vault(
      resolveDir: () async {
        resolves++;
        if (block) {
          block = false;
          entered.complete();
          await resume.future;
        }
        return r.dir.path;
      },
    );
    expect(await vault.unlock(vaultRealPin), isNotNull);
    block = true;
    final saving = r.saveProtected(vault);
    await entered.future; // 저장이 OS 작업 직전 단계에 걸려 있음
    final resolvesWhileSaving = resolves;

    final unlocking = vault.unlock(vaultDuressPin);
    await pumpEventQueue(times: 50);
    expect(
      resolves,
      resolvesWhileSaving,
      reason: 'the load is queued behind the save: it has not touched disk',
    );

    resume.complete();
    expect(await unlocking, isNotNull);
    await saving;
    expect(vault.isDecoyMode, isTrue);
    expect(
      r.file.readAsBytesSync(),
      before,
      reason: 'the old save never landed',
    );
  });

  test('save → erase → save leaves a working, unlocked vault', () async {
    final vault = await r.openReal();

    await vault.erase();
    expect(r.file.existsSync(), isFalse);
    vault.setPin(vaultRealPin);
    await r.saveProtected(vault);

    expect(r.file.existsSync(), isTrue);
    expect(r.noTmp(), isTrue);
  });
}
