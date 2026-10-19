import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:intragram/network/registry/incoming_path_resolver.dart';
import 'package:intragram/network/registry/incoming_session_files.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('session_files');
    IncomingSessionFiles.forget();
  });

  tearDown(() {
    IncomingSessionFiles.forget();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('sweep deletes only .intragram-*.part files', () async {
    File(p.join(dir.path, '.intragram-a-b.part')).writeAsStringSync('x');
    final keep = File(p.join(dir.path, 'photo.part'))..writeAsStringSync('x');
    final keep2 = File(p.join(dir.path, 'doc.txt'))..writeAsStringSync('x');

    final deleted = await IncomingSessionFiles.sweepOrphanPartials([dir.path]);

    expect(deleted, 1);
    expect(dir.listSync().map((e) => e.path).toSet(), {keep.path, keep2.path});
  });

  test('committed files are tracked and deleted on request', () async {
    final reserved = await IncomingPathResolver.reserveDestination(
      directory: dir.path,
      name: 'a.txt',
      attemptId: 'try1',
    );
    await reserved.partial.writeAsString('hello');
    final path = await IncomingPathResolver.commitDestination(
      reserved.partial,
      reserved.finalName,
    );
    final userFile = File(p.join(dir.path, 'mine.txt'))..writeAsStringSync('x');
    expect(IncomingSessionFiles.receivedCount, 1);

    await IncomingSessionFiles.deleteReceived();

    expect(File(path).existsSync(), isFalse);
    expect(userFile.existsSync(), isTrue);
    expect(IncomingSessionFiles.receivedCount, 0);
  });

  test('default sweep covers directories used this session', () async {
    final reserved = await IncomingPathResolver.reserveDestination(
      directory: dir.path,
      name: 'b.bin',
      attemptId: 'try2',
    );

    await IncomingSessionFiles.sweepOrphanPartials();

    expect(reserved.partial.existsSync(), isFalse);
  });
}
