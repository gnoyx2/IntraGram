import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/store/models.dart';
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

  test('save then load round-trips the snapshot', () async {
    await vault.save(snap());
    final loaded = await vault.load();

    expect(loaded, isNotNull);
    expect(loaded!.settings.enabled, isTrue);
    expect(loaded.conversations.single.id, 'c1');
    expect(loaded.conversations.single.outgoingTtlSeconds, 30);
    expect(loaded.messages.single.text, 'hello');
    expect(loaded.transfers.single.localPath, '/tmp/photo.jpg');
  });

  test('a restored conversation drops live state — archive only', () async {
    await vault.save(snap());
    final c = (await vault.load())!.conversations.single;

    expect(c.online, isFalse);
    expect(c.secure, isFalse);
    expect(c.verified, isFalse);
    expect(c.sas, isNull);
  });

  test('load returns null when the file is absent', () async {
    expect(await vault.load(), isNull);
  });

  test('load returns null on a corrupt file', () async {
    File('${dir.path}/vault.json').writeAsStringSync('{ not valid json');
    expect(await vault.load(), isNull);
  });

  test('erase removes the file', () async {
    await vault.save(snap());
    expect(File('${dir.path}/vault.json').existsSync(), isTrue);

    await vault.erase();
    expect(File('${dir.path}/vault.json').existsSync(), isFalse);
  });

  test('save leaves no .tmp behind (atomic rename)', () async {
    await vault.save(snap());
    expect(File('${dir.path}/vault.json.tmp').existsSync(), isFalse);
  });

  test('settings default off, and json flags round-trip', () {
    expect(const VaultSettings().enabled, isFalse);
    expect(const VaultSettings().stayConnectedInBackground, isFalse);
    final s = VaultSettings.fromJson(
      const VaultSettings(
        enabled: true,
        keepMessages: false,
        stayConnectedInBackground: true,
      ).toJson(),
    );
    expect(s.enabled, isTrue);
    expect(s.keepMessages, isFalse);
    expect(s.keepTransfers, isTrue);
    expect(s.stayConnectedInBackground, isTrue);
    // 예전 파일(키 없음)은 꺼짐으로 로드
    expect(
      VaultSettings.fromJson(
        const <String, dynamic>{},
      ).stayConnectedInBackground,
      isFalse,
    );
  });

  test('largeMessageMode defaults to inline and round-trips', () {
    expect(const VaultSettings().largeMessageMode, LargeMessageMode.inline);

    final s = VaultSettings.fromJson(
      const VaultSettings(
        largeMessageMode: LargeMessageMode.spillToFile,
      ).toJson(),
    );
    expect(s.largeMessageMode, LargeMessageMode.spillToFile);

    // 키가 없는 옛 파일은 inline으로 로드
    expect(
      VaultSettings.fromJson(const <String, dynamic>{}).largeMessageMode,
      LargeMessageMode.inline,
    );
  });
}
