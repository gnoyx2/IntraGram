import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/mobile_file_source.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/models.dart';

import 'support/mobile_source_rig.dart';
import 'support/transfer_rig.dart';

// 모바일 native 소스(OutgoingFileSource.releaseSource)가
// 소스가 전송이 끝나 reader가 다 닫힌 뒤 정확히 한 번 놓이고, 재시도할 수 있는 실패에선 남아 있다가 재시도가 같은 소스를
// 다시 여는지 봄. 방(pull) 두 명을 실제 서버·링크로 돌리고 가짜 MethodChannel의 호출 기록으로 순서·횟수를 검사
// (teardown은 mobile_source_teardown_test.dart)
void main() {
  late MobileSourceRig m;
  setUp(() async => m = await MobileSourceRig.create());

  // 멤버 0의 GET을 시작해 정지한 reader 상태로 붙잡아 둠
  Future<StreamSubscription<List<int>>> holdStalledGet(String id) async {
    m.fake.readGate = Completer<void>();
    final sub = (await m.openGet(
      id,
      0,
    ))!.body.listen((_) {}, onError: (Object _) {});
    await settle();
    return sub;
  }

  test('complete: released once, only after every reader is closed', () async {
    final id = await m.offer();
    await m.pullAll(id, 0);
    m.ack(id, 0);
    await settle();
    expect(m.fake.count('release'), 0, reason: 'member 1 has not received it');

    await m.pullAll(id, 1);
    m.ack(id, 1);
    await settle();

    expect(m.state(id), TransferState.complete);
    // 보내는 쪽이 제안 전에 SHA-256을 재려고 한 번 읽음(r1) + 멤버 둘
    expect(m.fake.count('open:'), 3);
    expect(m.fake.count('close:'), 3);
    expect(m.fake.count('release:s1'), 1);
    expect(m.closedBeforeRelease(), isTrue);
  });

  test('a retryable failure keeps the source; the retry reopens it and '
      'only success releases it', () async {
    final id = await m.offer();
    await m.pullAll(id, 0);
    m.ack(id, 0);
    await m.pullAll(id, 1); // EOF는 봤지만 ACK가 없음
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(m.state(id), TransferState.failed);
    expect(m.fake.count('release'), 0, reason: 'retryable → source retained');
    expect(m.rig.registry.outgoingSource(id), isNotNull);

    await m.rig.registry.retryTransfer(id);
    await m.pullAll(id, 1);
    m.ack(id, 1);
    await settle();

    expect(m.state(id), TransferState.complete);
    expect(
      m.fake.count('open:s1'),
      4,
      reason: 'digest read, member 0, member 1, retry',
    );
    expect(m.fake.count('release:s1'), 1);
    expect(m.closedBeforeRelease(), isTrue);
  });

  test('cancel with a stalled reader releases only after the reader '
      'closes', () async {
    final id = await m.offer();
    final sub = await holdStalledGet(id);
    expect(m.fake.count('open:s1'), 2, reason: 'digest read + the GET');

    m.rig.registry.cancelTransfer(id);
    await settle();
    expect(
      m.fake.count('close:'),
      1,
      reason: 'only the digest read closed; the GET is still stalled',
    );
    expect(m.fake.count('release'), 0, reason: 'reader still open');

    m.fake.readGate!.complete();
    await settle();

    expect(m.fake.count('release:s1'), 1);
    expect(m.fake.indexOf('close:r2'), lessThan(m.fake.indexOf('release:s1')));
    await sub.cancel();
  });

  test('discard (burn) waits for the reader, then releases once', () async {
    final id = await m.offer();
    final sub = await holdStalledGet(id);

    var discarded = false;
    final discarding = m.out.discard(id).then((_) => discarded = true);
    await settle();
    expect(discarded, isFalse, reason: 'the reader has not drained');
    expect(m.fake.count('release'), 0);

    m.fake.readGate!.complete();
    await discarding;

    expect(m.fake.count('release:s1'), 1);
    expect(m.fake.indexOf('close:r2'), lessThan(m.fake.indexOf('release:s1')));
    await sub.cancel();
  });

  test('a cancel racing a discard still calls releaseSource once', () async {
    var calls = 0;
    m.fake.pickCount = 1;
    final picked = (await MobileFileSource.pick()).single;
    await m.out.offerStreamSource(
      conversationId: m.roomId,
      name: picked.name,
      size: picked.size,
      openStream: picked.openRead,
      releaseSource: () {
        calls++;
        return picked.release();
      },
    );
    final id = m.rig.store.transfers.first.id;
    final sub = await holdStalledGet(id);

    m.rig.registry.cancelTransfer(id); // 정리 경로 하나
    final discarding = m.out.discard(id); // 같은 reader를 기다리는 두 번째 경로
    await settle();
    m.fake.readGate!.complete();
    await discarding;
    await settle();

    expect(calls, 1);
    await sub.cancel();
  });

  test('a peer reject releases the source that was never opened', () async {
    final rig = await TransferRig.create(); // 방이 아닌 1:1(push)
    m.fake.pickCount = 1;
    await rig.registry.offerStreamSources(
      rig.store.conversations.single.id,
      await MobileFileSource.pick(),
    );
    final t = rig.store.transfers.single;

    await rig.remote.sendFileReject(t.id, attemptId: t.attemptId!);
    await settle();

    expect(rig.store.transfer(t.id)!.state, TransferState.rejected);
    expect(m.fake.count('open:'), 0);
    expect(m.fake.count('release:s1'), 1);
  });
}
