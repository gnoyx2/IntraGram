import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/store/vault.dart';

import 'vault_snapshot.dart';

// vault_io_*_test.dart가 공유하는 리그: 임시 폴더 하나에 진짜 PIN/duress
// PIN으로 봉인한 아카이브를 만들고 진짜 세션으로 열린 Vault를 돌려줌
const vaultProtected = VaultSettings(enabled: true, pinProtected: true);
const vaultRealPin = '1357';
const vaultDuressPin = '2468';

class VaultOrderRig {
  late Directory dir;
  late File file;

  void setUp() {
    dir = Directory.systemTemp.createTempSync('intragram_vault_order_');
    file = File('${dir.path}/vault.json');
  }

  void tearDown() {
    Process.runSync('chmod', ['755', dir.path]);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  bool noTmp() => !dir.listSync().any((e) => e.path.endsWith('.tmp'));

  Vault vault() => Vault(resolveDir: () async => dir.path);

  Future<Vault> openReal() async {
    final seed = vault()
      ..setPin(vaultRealPin)
      ..setDecoyPin(vaultDuressPin);
    await seed.save(snap(settings: vaultProtected));
    final opened = vault();
    expect(await opened.unlock(vaultRealPin), isNotNull);
    return opened;
  }

  Future<void> saveProtected(Vault v) => v.save(snap(settings: vaultProtected));
}
