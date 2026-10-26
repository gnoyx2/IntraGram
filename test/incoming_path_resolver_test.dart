import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:intragram/network/registry/incoming_path_resolver.dart';

void main() {
  group('IncomingPathResolver partial-file staging', () {
    late Directory dir;
    // reserveDestination()이 승인 폴더를 resolveSymbolicLinks()로
    // canonical화하므로 반환 경로 검증도 그 기준으로 함
    // (macOS에선 Directory.systemTemp가 /var/...인데 실제론
    // /private/var/...의 심링크라 원본 dir.path 문자열로는 안 맞음)
    late String canonicalDir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ig_partial_');
      canonicalDir = await dir.resolveSymbolicLinks();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('reserves an attempt-scoped .part file, not the final name', () async {
      final reserved = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'video.mp4',
        attemptId: 'attempt-1',
      );
      expect(reserved.finalName, 'video.mp4');
      // 정확한 문자열이 아니라 계약을 봄: 이름은 제한된 시도 + 로컬 난수 접미사로 만들고 wire attempt를 파일명에 그대로 안 씀
      final basename = p.basename(reserved.partial.path);
      expect(basename, startsWith('.intragram-attempt-1-'));
      expect(basename, endsWith('.part'));
      expect(reserved.partial.existsSync(), isTrue);
      // 파셜 단계에선 최종 이름의 파일이 아직 존재하면 안 됨 (중단된 전송이 완성 파일인 척 노출되지 않는 계약)
      expect(File(p.join(canonicalDir, 'video.mp4')).existsSync(), isFalse);
    });

    test(
      'two concurrent accepts of the same name get separate partials',
      () async {
        final first = await IncomingPathResolver.reserveDestination(
          directory: dir.path,
          name: 'clip.mov',
          attemptId: 'attempt-a',
        );
        final second = await IncomingPathResolver.reserveDestination(
          directory: dir.path,
          name: 'clip.mov',
          attemptId: 'attempt-b',
        );
        expect(first.partial.path, isNot(second.partial.path));
        expect(first.partial.existsSync(), isTrue);
        expect(second.partial.existsSync(), isTrue);
      },
    );

    test(
      'sanitizes a hostile attemptId before it reaches the filesystem',
      () async {
        final reserved = await IncomingPathResolver.reserveDestination(
          directory: dir.path,
          name: 'note.txt',
          attemptId: '../../evil',
        );
        expect(p.isWithin(canonicalDir, reserved.partial.path), isTrue);
        expect(reserved.partial.path.contains('..'), isFalse);
      },
    );

    test('commit renames the partial into the reserved final name', () async {
      final reserved = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'doc.pdf',
        attemptId: 'attempt-1',
      );
      await reserved.partial.writeAsString('payload');
      final committed = await IncomingPathResolver.commitDestination(
        reserved.partial,
        reserved.finalName,
      );
      expect(committed, p.join(canonicalDir, 'doc.pdf'));
      expect(File(committed).readAsStringSync(), 'payload');
      expect(reserved.partial.existsSync(), isFalse);
    });

    test(
      'commit suffixes on collision and preserves the existing file',
      () async {
        final existing = File(p.join(dir.path, 'doc.pdf'));
        await existing.writeAsString('someone else already has this name');

        final reserved = await IncomingPathResolver.reserveDestination(
          directory: dir.path,
          name: 'doc.pdf',
          attemptId: 'attempt-2',
        );
        await reserved.partial.writeAsString('my payload');
        final committed = await IncomingPathResolver.commitDestination(
          reserved.partial,
          reserved.finalName,
        );

        expect(committed, p.join(canonicalDir, 'doc (1).pdf'));
        expect(
          existing.readAsStringSync(),
          'someone else already has this name',
        );
        expect(File(committed).readAsStringSync(), 'my payload');
      },
    );

    test('two attempts committing the same name both land, suffixed', () async {
      final first = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'clip.mov',
        attemptId: 'attempt-a',
      );
      final second = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'clip.mov',
        attemptId: 'attempt-b',
      );
      await first.partial.writeAsString('a');
      await second.partial.writeAsString('b');

      final firstCommitted = await IncomingPathResolver.commitDestination(
        first.partial,
        first.finalName,
      );
      final secondCommitted = await IncomingPathResolver.commitDestination(
        second.partial,
        second.finalName,
      );

      expect(firstCommitted, isNot(secondCommitted));
      expect(File(firstCommitted).readAsStringSync(), 'a');
      expect(File(secondCommitted).readAsStringSync(), 'b');
    });

    test(
      'a broken symlink at the final name is treated as occupied',
      () async {
        final linkPath = p.join(dir.path, 'photo.png');
        // 존재하지 않는 대상을 가리키는 심볼릭 링크: 파일시스템 관점에서는
        // 여전히 "이미 있는 항목"이라 exclusive create가 막혀야 함
        Link(linkPath).createSync(p.join(dir.path, 'nowhere'));

        final reserved = await IncomingPathResolver.reserveDestination(
          directory: dir.path,
          name: 'photo.png',
          attemptId: 'attempt-3',
        );
        await reserved.partial.writeAsString('bytes');
        final committed = await IncomingPathResolver.commitDestination(
          reserved.partial,
          reserved.finalName,
        );
        expect(committed, p.join(canonicalDir, 'photo (1).png'));
      },
      testOn: '!windows',
    );

    // Windows에선 폴더 위 create가 EEXIST가 아닌 코드로 실패해서 이름 확인이 따로 있어야 함
    test('a folder at the final name is treated as occupied', () async {
      Directory(p.join(dir.path, 'notes.txt')).createSync();

      final reserved = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'notes.txt',
        attemptId: 'attempt-4',
      );
      await reserved.partial.writeAsString('bytes');
      final committed = await IncomingPathResolver.commitDestination(
        reserved.partial,
        reserved.finalName,
      );
      expect(committed, p.join(canonicalDir, 'notes (1).txt'));
      expect(Directory(p.join(canonicalDir, 'notes.txt')).existsSync(), isTrue);
    });

    // 위 테스트는 POSIX에선 EEXIST로도 통과해서 Windows 경로(접근 거부 5)를 어느 OS에서나 따로 봄
    test('a folder is taken even when the error is not EEXIST', () {
      final folder = Directory(p.join(dir.path, 'notes.txt'))..createSync();
      const denied = OSError('Access is denied', 5);
      expect(IncomingPathResolver.isNameCollision(folder.path, denied), isTrue);
      expect(
        IncomingPathResolver.isNameCollision(
          p.join(dir.path, 'missing.txt'),
          denied,
        ),
        isFalse,
      );
    });
  });
}
