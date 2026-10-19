import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/identity_store.dart';

void main() {
  late Directory dir;
  late IdentityStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('intragram_identity');
    store = IdentityStore(resolveDir: () async => dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('save then load round-trips the alias', () async {
    await store.saveAlias('wise-elk-19');
    expect(await store.loadAlias(), 'wise-elk-19');
  });

  test('loadAlias returns null when no file was ever saved', () async {
    expect(await store.loadAlias(), isNull);
  });

  test('loadAlias returns null on a corrupt file', () async {
    File('${dir.path}/identity.json').writeAsStringSync('{ not valid json');
    expect(await store.loadAlias(), isNull);
  });

  test('clear removes the file and later loads see null again', () async {
    await store.saveAlias('wise-elk-19');
    expect(File('${dir.path}/identity.json').existsSync(), isTrue);

    await store.clear();
    expect(File('${dir.path}/identity.json').existsSync(), isFalse);
    expect(await store.loadAlias(), isNull);
  });

  test('save leaves no .tmp behind (atomic rename)', () async {
    await store.saveAlias('wise-elk-19');
    expect(File('${dir.path}/identity.json.tmp').existsSync(), isFalse);
  });

  test(
    'clear reports an undeletable path and still removes its temp',
    () async {
      Directory('${dir.path}/identity.json').createSync();
      final tmp = File('${dir.path}/identity.json.tmp')..writeAsStringSync('x');
      await expectLater(store.clear(), throwsA(isA<FileSystemException>()));
      expect(tmp.existsSync(), isFalse);
    },
  );
}
