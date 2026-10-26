import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/file_streamer.dart'
    show TransferCleanupException;
import 'package:intragram/network/registry/outgoing_transfers.dart';

import 'support/mobile_source_rig.dart';

// 세션 teardown(disposeAll)이 stage된 모든 소스의 native 자원을
// 놓고, 끝나지 않은 release도 기다리며, release 실패를 삼키지 않음
void main() {
  late MobileSourceRig m;
  setUp(() async => m = await MobileSourceRig.create());

  test('disposeAll releases every staged source before it returns', () async {
    await m.offer(count: 2);
    expect(m.fake.count('release'), 0);

    await m.rig.registry.disposeAll();

    expect(m.fake.count('release:s1'), 1);
    expect(m.fake.count('release:s2'), 1);
  });

  test('disposeAll waits for a release that is still in flight', () async {
    final id = await m.offer();
    m.fake.releaseGate = Completer<void>();
    // 두 멤버가 다 받으면 source가 빠지며 release가 시작되지만 gate로 안 끝남
    for (final i in [0, 1]) {
      await m.pullAll(id, i);
      m.ack(id, i);
    }
    await settle();
    expect(m.fake.count('release:s1'), 1, reason: 'started, not finished');

    var disposed = false;
    final disposing = m.rig.registry.disposeAll().then((_) => disposed = true);
    await settle();
    expect(disposed, isFalse, reason: 'teardown must not outrun the release');

    m.fake.releaseGate!.complete();
    await disposing;
    expect(disposed, isTrue);
  });

  test('a failing release is reported by teardown, not hidden', () async {
    await m.offer();
    m.fake.failRelease.add('s1');

    await expectLater(
      m.rig.registry.disposeAll(),
      throwsA(isA<TransferCleanupException>()),
    );
  });

  test('a failing release on link close still releases the other sources and '
      'is reported by teardown', () async {
    await m.offer(count: 2);
    m.fake.failRelease.add('s1');

    await m.out.handleLinkClosed(m.roomId);

    expect(m.fake.count('release:s1'), 1);
    expect(m.fake.count('release:s2'), 1);
    await expectLater(
      m.rig.registry.disposeAll(),
      throwsA(isA<TransferCleanupException>()),
    );
  });
}
