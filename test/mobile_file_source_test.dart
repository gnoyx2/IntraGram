import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/mobile_file_source.dart';

import 'support/fake_file_source_channel.dart';

// 모바일 native 소스 lifecycle: 가짜 MethodChannel의 호출 기록으로
// open -> read -> close -> release의 순서/횟수를 검사하고,
// releaseAll의 generation이 늦게 도착한 pick/open 결과를 막는지 확인
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFileSourceChannel fake;
  setUp(() {
    fake = FakeFileSourceChannel()..install();
  });

  Future<MobileFileSource> pickOne() async =>
      (await MobileFileSource.pick()).single;

  test('a full read is open → read… → close, the reader closed once', () async {
    final source = await pickOne();

    final bytes = await source.openRead().expand((c) => c).toList();

    expect(bytes, hasLength(fake.fileSize));
    expect(fake.log, [
      'pick',
      'open:s1',
      'read:r1',
      'read:r1',
      'read:r1', // 세 번째 read가 EOF(null)
      'close:r1',
    ]);
  });

  test('cancelling mid-stream closes the reader once and does not release '
      'the source', () async {
    final source = await pickOne();
    final iterator = StreamIterator(source.openRead());
    expect(await iterator.moveNext(), isTrue);

    await iterator.cancel();

    expect(fake.count('close:r1'), 1);
    expect(fake.count('release'), 0, reason: 'the source may still be retried');
  });

  test('a retry reopens the same source with a fresh reader', () async {
    final source = await pickOne();

    await source.openRead().drain<void>();
    await source.openRead().drain<void>();

    expect(fake.count('open:s1'), 2);
    expect(fake.count('close:'), 2);
    expect(fake.count('release'), 0);
  });

  test(
    'release is idempotent — one native call however often it is asked',
    () async {
      final source = await pickOne();

      await Future.wait([source.release(), source.release()]);
      await source.release();

      expect(fake.count('release:s1'), 1);
    },
  );

  test('a pick result that arrives after releaseAll is dropped and its '
      'sources released', () async {
    fake
      ..pickGate = Completer<void>()
      ..pickCount = 2;
    final picking = MobileFileSource.pick();
    await pumpEventQueue();

    await MobileFileSource.releaseAll();
    fake.pickGate!.complete();

    expect(await picking, isEmpty, reason: 'nobody may adopt a dead pick');
    expect(
      fake.log,
      containsAllInOrder(['pick', 'releaseAll', 'release:s1', 'release:s2']),
    );
  });

  test('a source from before releaseAll can no longer be opened', () async {
    final source = await pickOne();
    await MobileFileSource.releaseAll();

    await expectLater(source.openRead().toList(), throwsStateError);

    expect(fake.count('open:'), 0, reason: 'no native open for a dead source');
  });

  test('an open that finishes after releaseAll is closed at once and the '
      'stream ends in error, not as an empty file', () async {
    final source = await pickOne();
    fake.openGate = Completer<void>();
    final reading = source.openRead().toList();
    await pumpEventQueue();

    await MobileFileSource.releaseAll();
    fake.openGate!.complete();

    await expectLater(reading, throwsStateError);
    expect(fake.log, containsAllInOrder(['open:s1', 'releaseAll', 'close:r1']));
    expect(fake.count('read:'), 0, reason: 'the late reader was never read');
  });

  test('releaseEach releases every source even if one release fails', () async {
    fake.pickCount = 3;
    final sources = await MobileFileSource.pick();
    fake.failRelease.add('s2');

    await MobileFileSource.releaseEach(sources);

    expect(fake.count('release:'), 3);
  });
}
