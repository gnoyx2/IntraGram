import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/path_safety.dart';
import 'package:intragram/network/file_streamer.dart';

void main() {
  group('safeBasename', () {
    test('strips directory components and separators', () {
      expect(safeBasename('../../../../Users/victim/.zshrc'), '_.zshrc');
      expect(safeBasename(r'..\..\evil.exe'), 'evil.exe');
      expect(safeBasename('/etc/cron.d/payload'), 'payload');
      expect(safeBasename('C:\\Windows\\system32\\x.dll'), 'x.dll');
    });

    test('removes NUL and control characters', () {
      expect(safeBasename('inv\u0000oice.pdf'), 'invoice.pdf');
      expect(safeBasename('a\tb\nc.txt'), 'abc.txt');
    });

    test('never returns empty, dot, or dot-dot', () {
      expect(safeBasename(''), 'received-file');
      expect(safeBasename('..'), 'received-file');
      expect(safeBasename('.'), 'received-file');
      expect(safeBasename('////'), 'received-file');
    });

    test('caps very long names but keeps the extension', () {
      final name = safeBasename('${'a' * 500}.tar.gz');
      expect(name.length, lessThanOrEqualTo(200));
      expect(name.endsWith('.gz'), isTrue);
    });
  });

  group('resolveWithin', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('intragram_rw'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a benign name resolves inside the directory', () {
      final path = resolveWithin(dir.path, 'photo.jpg');
      expect(path.endsWith('photo.jpg'), isTrue);
      expect(path.startsWith(dir.path), isTrue);
    });

    test('a traversal attempt still lands inside (sanitised)', () {
      final path = resolveWithin(dir.path, '../../../../etc/passwd');
      expect(path, '${dir.path}${Platform.pathSeparator}passwd');
    });

    test('a dot name is coerced to a real file inside the directory', () {
      final path = resolveWithin(dir.path, '.');
      expect(path.endsWith('received-file'), isTrue);
      expect(path.startsWith(dir.path), isTrue);
    });
  });

  group('FileStreamer.receive size enforcement', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('intragram_fs'));
    tearDown(() => dir.deleteSync(recursive: true));

    Stream<List<int>> bytes(int total, {int chunk = 4096}) async* {
      var sent = 0;
      while (sent < total) {
        final n = (total - sent) < chunk ? (total - sent) : chunk;
        yield List<int>.filled(n, 7);
        sent += n;
      }
    }

    test('writes a file that matches the declared size', () async {
      final dest = '${dir.path}/ok.bin';
      final written = await FileStreamer.receive(
        body: bytes(10000),
        transferId: 'ok',
        attemptId: 'a-ok',
        destinationPath: dest,
        declaredSize: 10000,
      );
      expect(written, 10000);
      expect(File(dest).lengthSync(), 10000);
    });

    test(
      'aborts and deletes the file when the body exceeds the declaration',
      () async {
        final dest = '${dir.path}/toobig.bin';
        await expectLater(
          FileStreamer.receive(
            body: bytes(5 * 1024 * 1024),
            transferId: 'toobig',
            attemptId: 'a-toobig',
            destinationPath: dest,
            declaredSize: 1024, // 피어는 1 KB라 해놓고 5 MB를 보냄
          ),
          throwsA(isA<SecurityException>()),
        );
        expect(File(dest).existsSync(), isFalse);
      },
    );

    test('accepts a large declared size — no hard ceiling (LocalSend-style), '
        'as long as the body actually delivers exactly that much '
        '(a declared size is a promise, not just an upper bound)', () async {
      final dest = '${dir.path}/huge-decl.bin';
      const declared = 10 * 1024 * 1024; // 이 값에 상한을 거는 코드 경로가 없음
      final written = await FileStreamer.receive(
        body: bytes(declared),
        transferId: 'huge-decl',
        attemptId: 'a-huge-decl',
        destinationPath: dest,
        declaredSize: declared,
      );
      expect(written, declared);
      expect(File(dest).lengthSync(), declared);
    });

    test('a short EOF (less than declared) is rejected', () async {
      final dest = '${dir.path}/short.bin';
      await expectLater(
        FileStreamer.receive(
          body: bytes(4096),
          transferId: 'short',
          attemptId: 'a-short',
          destinationPath: dest,
          declaredSize: 8192, // 피어는 8 KiB라 해놓고 4 KiB만 보냄
        ),
        throwsA(isA<SecurityException>()),
      );
      expect(File(dest).existsSync(), isFalse);
    });

    test('still rejects a negative declared size', () async {
      await expectLater(
        FileStreamer.receive(
          body: bytes(1),
          transferId: 'neg',
          attemptId: 'a-neg',
          destinationPath: '${dir.path}/neg.bin',
          declaredSize: -1,
        ),
        throwsA(isA<SecurityException>()),
      );
    });
  });
}
