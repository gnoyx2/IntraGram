import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/private_dir.dart';

void main() {
  late Directory root;
  late Directory docs;
  late Directory support;

  setUp(() {
    root = Directory.systemTemp.createTempSync('intragram_private');
    docs = Directory('${root.path}/docs')..createSync();
    support = Directory('${root.path}/support')..createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  File at(Directory d, String name) => File('${d.path}/$name');

  test('moves vault and identity out of Documents once', () async {
    at(docs, 'vault.json').writeAsStringSync('{"enc":true}');
    at(docs, 'identity.json').writeAsStringSync('{"alias":"a"}');
    at(docs, 'vault.json.tmp').writeAsStringSync('half');
    at(docs, 'photo.jpg').writeAsStringSync('received');

    await migratePrivateFiles(from: docs.path, to: support.path);

    expect(at(support, 'vault.json').readAsStringSync(), '{"enc":true}');
    expect(at(support, 'identity.json').readAsStringSync(), '{"alias":"a"}');
    expect(at(docs, 'vault.json').existsSync(), isFalse);
    expect(at(docs, 'vault.json.tmp').existsSync(), isFalse);
    expect(at(docs, 'identity.json').existsSync(), isFalse);
    expect(at(docs, 'photo.jpg').existsSync(), isTrue);
    expect(at(support, 'vault.json.tmp').existsSync(), isFalse);
  });

  // Windows: 예전 로밍(%APPDATA%) 자리의 저장 폴더 기록도 로컬(%LOCALAPPDATA%)로 옮김
  test('the remembered download folders move with the other files', () async {
    at(docs, 'download_directories.json').writeAsStringSync('["C:/x"]');

    await migratePrivateFiles(from: docs.path, to: support.path);

    expect(
      at(support, 'download_directories.json').readAsStringSync(),
      '["C:/x"]',
    );
    expect(at(docs, 'download_directories.json').existsSync(), isFalse);
  });

  test('a newer file in the new place wins over the old copy', () async {
    at(docs, 'vault.json').writeAsStringSync('old');
    at(support, 'vault.json').writeAsStringSync('new');

    await migratePrivateFiles(from: docs.path, to: support.path);

    expect(at(support, 'vault.json').readAsStringSync(), 'new');
    expect(at(docs, 'vault.json').existsSync(), isFalse);
  });

  test('nothing to move is a no-op', () async {
    await migratePrivateFiles(from: docs.path, to: support.path);
    expect(support.listSync(), isEmpty);
  });
}
