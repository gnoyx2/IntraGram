import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/temp_sweep.dart';

// 시작·패닉 때 플러그인 임시 사본을 지움: 앱 전용 임시 폴더만, 공용 임시 폴더는 안 건드림
void main() {
  late Directory caches;
  late Directory tmp;

  setUp(() {
    caches = Directory.systemTemp.createTempSync('caches');
    tmp = Directory.systemTemp.createTempSync('tmp');
  });
  tearDown(() {
    for (final d in [caches, tmp]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  File touch(Directory dir, String path) => File('${dir.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync('plaintext');

  test('every app-private temp folder is emptied', () async {
    touch(caches, 'share_plus/report.pdf');
    touch(tmp, 'MediaCache/CachedMedia-1');
    touch(tmp, 'Drops/1/photo.heic');
    touch(tmp, 'loose.wav');

    await sweepAppTemp(tempDirs: [caches, tmp], appPrivate: true);

    expect(caches.listSync(), isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect(tmp.existsSync(), isTrue, reason: 'the folder itself stays');
  });

  test('a shared temp folder is left alone', () async {
    final other = touch(tmp, 'pas1A2B.tmp');
    final folder = touch(tmp, 'someone/else.txt');

    await sweepAppTemp(tempDirs: [tmp], appPrivate: false);

    expect(other.existsSync(), isTrue);
    expect(folder.existsSync(), isTrue);
  });

  test('Apple platforms sweep tmp/ as well as the plugin temp folder', () {
    final dirs = tempDirsFor(caches, apple: true).map((d) => d.path);
    expect(dirs, containsAll([caches.path, Directory.systemTemp.path]));
    expect(tempDirsFor(caches, apple: false).map((d) => d.path), [caches.path]);
  });

  test('only a sandboxed macOS app owns its tmp/', () {
    const sandbox = {'APP_SANDBOX_CONTAINER_ID': 'x'};
    expect(tempIsAppPrivate('ios', const {}), isTrue);
    expect(tempIsAppPrivate('android', const {}), isTrue);
    expect(tempIsAppPrivate('macos', sandbox), isTrue);
    expect(tempIsAppPrivate('macos', const {}), isFalse);
    expect(tempIsAppPrivate('windows', sandbox), isFalse);
    expect(tempIsAppPrivate('linux', const {}), isFalse);
  });
}
