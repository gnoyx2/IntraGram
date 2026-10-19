import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/store/vault.dart';

import 'support/vault_snapshot.dart';

const _pinned = VaultSettings(enabled: true, pinProtected: true);

void main() {
  late Directory dir;
  late File file;

  Vault open() => Vault(resolveDir: () async => dir.path);
  Map<String, dynamic> readFile() =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  Future<List<int>> pbkdf2(String pin, Map<String, dynamic> map) async {
    final salt = base64.decode((map['kdf'] as Map)['salt'] as String);
    final key = await CryptoEngine.deriveKeyFromPin(pin, salt);
    return key.extractBytes();
  }

  // 진짜 1357, duress 2468로 봉인한 파일
  Future<void> seed() async {
    final v = open()..setPin('1357');
    expect(v.setDecoyPin('2468'), isTrue);
    await v.save(snap(settings: _pinned));
  }

  // dv 없이 PBKDF2 원본을 dchk에 담던 옛 형식으로 되돌림
  Future<void> downgrade(String dchkPin) async {
    final map = readFile()
      ..remove('dv')
      ..remove('ds');
    map['dchk'] = base64.encode(await pbkdf2(dchkPin, map));
    file.writeAsStringSync(jsonEncode(map));
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_dchk');
    file = File('${dir.path}/vault.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('setPin rejects the duress PIN set in this session', () {
    final v = open()..setPin('1357');
    expect(v.setDecoyPin('2468'), isTrue);
    expect(v.setPin('2468'), isFalse);
    expect(v.setPin('9999'), isTrue);
  });

  test('isDecoyPin still catches the duress PIN after a restart', () async {
    await seed();
    final v = open();
    expect(await v.unlock('1357'), isNotNull);
    expect(await v.isDecoyPin('2468'), isTrue);
    expect(await v.isDecoyPin('9999'), isFalse);
  });

  test('dchk is not the PBKDF2 key of the duress PIN', () async {
    await seed();
    final map = readFile();
    expect(map['dv'], 2);
    expect(
      base64.decode(map['dchk'] as String),
      isNot(await pbkdf2('2468', map)),
    );

    final v = open();
    expect(await v.unlock('2468'), isNotNull);
    expect(v.isDecoyMode, isTrue);
  });

  test('legacy dchk keeps working and is rewritten as v2', () async {
    await seed();
    await downgrade('2468');

    final decoy = open();
    expect(await decoy.unlock('2468'), isNotNull);
    expect(decoy.isDecoyMode, isTrue);

    final real = open();
    final snapshot = await real.unlock('1357');
    expect(snapshot, isNotNull);
    expect(real.needsRewrite, isTrue);
    await real.save(snapshot!);
    expect(real.needsRewrite, isFalse);
    expect(readFile()['dv'], 2);

    final again = open();
    expect(await again.unlock('2468'), isNotNull);
    expect(again.isDecoyMode, isTrue);
  });

  test('legacy dchk equal to the real key rotates the salt', () async {
    await seed();
    await downgrade('1357');
    final oldSalt = (readFile()['kdf'] as Map)['salt'];

    final real = open();
    final snapshot = await real.unlock('1357');
    await real.save(snapshot!);

    final map = readFile();
    expect((map['kdf'] as Map)['salt'], isNot(oldSalt));
    expect(
      base64.decode(map['dchk'] as String),
      isNot(await pbkdf2('1357', map)),
    );
    expect(await open().unlock('1357'), isNotNull);
  });
}
