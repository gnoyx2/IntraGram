import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/vault.dart';

import 'support/vault_snapshot.dart';

void main() {
  test('duress transition must invalidate already queued real save', () async {
    final dir = Directory.systemTemp.createTempSync('intragram_vault_');
    addTearDown(() => dir.deleteSync(recursive: true));
    const protected = VaultSettings(enabled: true, pinProtected: true);
    final original = Vault(resolveDir: () async => dir.path);
    original.setPin('1357');
    original.setDecoyPin('2468');
    await original.save(snap(settings: protected));
    final file = File('${dir.path}/vault.json');

    var block = false;
    final entered = Completer<void>();
    final resume = Completer<void>();
    final vault = Vault(
      resolveDir: () async {
        if (block) {
          block = false;
          entered.complete();
          await resume.future;
        }
        return dir.path;
      },
    );
    expect(await vault.unlock('1357'), isNotNull);
    final before = file.readAsBytesSync();
    final beforeModified = file.lastModifiedSync();
    block = true;
    final saving = vault.save(snap(settings: protected));
    await entered.future;
    // 판독(Vault.load의 실제 작업)은 저장/삭제와 같은 큐에서 이미 돌고 있던 저장 뒤에 서서 그 저장이 풀려야 전이가 끝남
    // 전이는 시작 즉시(동기) epoch를 올려서 큐의 옛 저장을 무효화함
    final unlocking = vault.unlock('2468');
    resume.complete();
    expect(await unlocking, isNotNull);
    expect(vault.isDecoyMode, isTrue);
    await saving;
    expect(
      file.readAsBytesSync(),
      before,
      reason: 'the real archive must not be rewritten after entering decoy',
    );
    expect(file.lastModifiedSync(), beforeModified);
    expect(
      dir.listSync().where((e) => e.path.endsWith('.tmp')),
      isEmpty,
      reason: 'no temp file left behind',
    );
  });
}
