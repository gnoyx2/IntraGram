import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:intragram/network/file_streamer.dart'
    show TransferCleanupException;
import 'package:intragram/network/registry/incoming_path_resolver.dart';

import 'support/chmod_injection.dart';

// 로컬 저장(음성 수동 저장)과 커밋의 실패 정리: 커밋 못 한 파셜은 어떤 실패/중단에서도
// 지워지고, 사용자 파일은 절대 안 건드리며, 정리 자체가 실패하면 삼키지 않고 드러남

// delete()가 실패하는 파일 (placeholder 정리 실패를 결정적으로 만듦)
class _UndeletableFile implements File {
  _UndeletableFile(this._inner);
  final File _inner;

  @override
  String get path => _inner.path;
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _inner.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  bool existsSync() => _inner.existsSync();
  @override
  int lengthSync() => _inner.lengthSync();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      throw const FileSystemException('injected: cannot delete placeholder');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('intragram_save_'));
  tearDown(() {
    Process.runSync('chmod', ['755', dir.path]);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> names() =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  Future<String?> save({
    String name = 'note.ogg',
    List<int> bytes = const [1, 2, 3],
    bool Function()? wanted,
  }) => IncomingPathResolver.saveBytes(
    directory: dir.path,
    name: name,
    bytes: bytes,
    isStillWanted: wanted ?? () => true,
  );

  test('a save commits the bytes and leaves no partial behind', () async {
    final path = await save(bytes: [9, 8, 7]);

    expect(File(path!).readAsBytesSync(), [9, 8, 7]);
    expect(names(), ['note.ogg']);
  });

  test('a screen closed while the chooser was open writes nothing', () async {
    final path = await save(wanted: () => false);

    expect(path, isNull);
    expect(names(), isEmpty, reason: 'no bytes, no partial, no final file');
  });

  test('a session burned between reserve and write is not saved', () async {
    var calls = 0;
    // reserve 뒤 첫 확인은 통과, 쓰기 뒤 두 번째 확인은 거부
    final path = await save(wanted: () => ++calls < 2);

    expect(path, isNull);
    expect(names(), isEmpty, reason: 'the written partial was deleted');
  });

  test('a commit failure deletes the reserved partial and keeps every user '
      'file', () async {
    // 최종 이름 후보 100개(원본, (1)…(99))가 전부 이미 있음 → 커밋이 소진돼 실패함
    final taken = <String>[
      'note.ogg',
      for (var i = 1; i < 100; i++) 'note ($i).ogg',
    ];
    for (final name in taken) {
      File(p.join(dir.path, name)).writeAsStringSync('user file $name');
    }

    await expectLater(save(), throwsStateError);

    expect(names(), List<String>.of(taken)..sort());
    expect(
      File(p.join(dir.path, 'note.ogg')).readAsStringSync(),
      'user file note.ogg',
    );
  });

  test(
    'a partial that cannot be deleted is reported with the original error',
    () async {
      // reserve 뒤 폴더를 잠가서 커밋(placeholder 생성)과 파셜 삭제가 둘 다 거부됨
      Object? error;
      try {
        await save(
          wanted: () {
            Process.runSync('chmod', ['555', dir.path]);
            return true;
          },
        );
      } on Object catch (e) {
        error = e;
      }

      expect(error, isA<TransferCleanupException>());
      final cleanup = error! as TransferCleanupException;
      expect(cleanup.original, isA<FileSystemException>());
      expect(cleanup.failures.single, isA<FileSystemException>());
      expect(
        names().where((n) => n.endsWith('.part')),
        hasLength(1),
        reason: 'still there — reported, not silently forgotten',
      );
    },
    skip: chmodInjectionSkip,
  );

  group('commitDestination rename failure', () {
    test('removes only its own placeholder and leaves the user file', () async {
      final existing = File(p.join(dir.path, 'doc.pdf'))
        ..writeAsStringSync('mine');
      final reserved = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'doc.pdf',
        attemptId: 'a1',
      );
      reserved.partial.deleteSync(); // 원본이 사라져 rename이 실패함

      await expectLater(
        IncomingPathResolver.commitDestination(
          reserved.partial,
          reserved.finalName,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(names(), ['doc.pdf'], reason: 'no leftover placeholder');
      expect(existing.readAsStringSync(), 'mine');
    });

    test('a placeholder that cannot be removed is reported with the rename '
        'error', () async {
      File(p.join(dir.path, 'doc.pdf')).writeAsStringSync('mine');
      final reserved = await IncomingPathResolver.reserveDestination(
        directory: dir.path,
        name: 'doc.pdf',
        attemptId: 'a2',
      );
      reserved.partial.deleteSync(); // rename 실패 유도

      Object? error;
      await IOOverrides.runZoned(
        () async {
          try {
            await IncomingPathResolver.commitDestination(
              reserved.partial,
              reserved.finalName,
            );
          } on Object catch (e) {
            error = e;
          }
        },
        // 오버라이드 안에서 `File(path)`를 다시 부르면 무한 재귀: root zone에서 진짜
        // 파일을 만들어 감쌈
        createFile: (path) {
          final real = Zone.root.run(() => File(path));
          return path.endsWith('doc (1).pdf') ? _UndeletableFile(real) : real;
        },
      );

      expect(error, isA<TransferCleanupException>());
      final cleanup = error! as TransferCleanupException;
      expect(cleanup.original, isA<FileSystemException>());
      expect(cleanup.failures.single, isA<FileSystemException>());
    });
  });
}
