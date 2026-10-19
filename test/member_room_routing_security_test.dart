import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

// 방 멤버가 내는 파일의 호스트 라우팅 인가: 잘못된 대상·다른 멤버·낡은 attempt의
// 프레임은 중계도 상태 변경도 없어야 하고, 정당한 별도 offer는 막히면 안 됨
void main() {
  final m1 = MemberRoomRig.memberId(0);
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);
  late MemberRoomRig r;
  setUp(() async => r = await MemberRoomRig.create());

  test(
    'other members still get their offer after the host accepted its own',
    () async {
      await r.rawOffer(id: 't1', attempt: 'aH', to: r.hostId);
      await pumpEventQueue(times: 40);
      expect(r.hostCopy('t1')?.attemptId, 'aH');
      expect(
        r.copyAt(1, 't1'),
        isNull,
        reason: 'a host-addressed offer is not relayed',
      );
      r.rig.store.updateTransfer(
        't1',
        (t) => t.copyWith(state: TransferState.transferring),
      );

      await r.rawOffer(id: 't1', attempt: 'aM2', to: m2);
      await r.rawOffer(id: 't1', attempt: 'aM3', to: m3);
      await pumpEventQueue(times: 60);

      expect(r.copyAt(1, 't1')?.attemptId, 'aM2');
      expect(r.copyAt(2, 't1')?.attemptId, 'aM3');
      expect(r.hostCopy('t1')?.attemptId, 'aH');
      expect(r.hostCopy('t1')?.state, TransferState.transferring);
      expect(r.routeCount, 2);

      await r.rig.remotes[1].sendFileAccept(
        't1',
        attemptId: 'aM2',
        pushToken: 'x',
      );
      await pumpEventQueue(times: 40);
      expect(r.senderEvents, ['accept:c:aM2']);
    },
  );

  test('a routed offer that disagrees with the host copy is refused', () async {
    await r.rawOffer(id: 't2', attempt: 'aH', to: r.hostId);
    await pumpEventQueue(times: 40);
    await r.rawOffer(id: 't2', attempt: 'aM2', to: m2, name: 'other.bin');
    await pumpEventQueue(times: 60);
    expect(r.copyAt(1, 't2'), isNull);
    expect(r.routeCount, 0);
    expect(r.senderEvents, ['cancel:c:aM2'], reason: 'the sender is told');
  });

  test(
    'frames from a member that is not the target never reach anyone',
    () async {
      await r.rawOffer(id: 't3', attempt: 'aM2', to: m2);
      await pumpEventQueue(times: 60);
      expect(r.copyAt(1, 't3')?.attemptId, 'aM2');

      final other = r.rig.remotes[2]; // M3는 aM2의 대상이 아님
      await other.sendFileAccept('t3', attemptId: 'aM2', pushToken: 'x');
      await other.sendFileReceived('t3', attemptId: 'aM2');
      await other.sendFileRetry('t3', attemptId: 'aM2');
      await other.sendFileReject('t3', attemptId: 'aM2');
      await other.sendFileCancel('t3', attemptId: 'aM2');
      await pumpEventQueue(times: 60);

      expect(r.senderEvents, isEmpty);
      expect(
        r.memberEvents[1],
        isEmpty,
        reason: 'the target copy is not cancelled',
      );
      expect(r.routeCount, 1, reason: 'the route survives the bogus frames');

      await r.rig.remotes[1].sendFileAccept(
        't3',
        attemptId: 'aM2',
        pushToken: 'x',
      );
      await pumpEventQueue(times: 40);
      expect(r.senderEvents, ['accept:c:aM2']);
    },
  );

  test(
    'frames of a stale attempt are dropped once the offer is re-sent',
    () async {
      await r.rawOffer(id: 't4', attempt: 'a1', to: m2);
      await pumpEventQueue(times: 60);
      await r.rawOffer(id: 't4', attempt: 'a2', to: m2);
      await pumpEventQueue(times: 60);
      expect(r.copyAt(1, 't4')?.attemptId, 'a2');
      expect(r.copyAt(1, 't4')?.pullToken, 'tok-a2');
      expect(r.routeCount, 1, reason: 'the old attempt route is replaced');

      await r.rig.remotes[1].sendFileAccept(
        't4',
        attemptId: 'a1',
        pushToken: 'x',
      );
      await r.rig.remotes[1].sendFileReceived('t4', attemptId: 'a1');
      await pumpEventQueue(times: 40);
      expect(r.senderEvents, isEmpty);

      await r.rig.remotes[1].sendFileAccept(
        't4',
        attemptId: 'a2',
        pushToken: 'x',
      );
      await pumpEventQueue(times: 40);
      expect(r.senderEvents, ['accept:c:a2']);
    },
  );

  test(
    'cancel is relayed both ways for a routed attempt and ends the route',
    () async {
      await r.rawOffer(id: 't5', attempt: 'aM2', to: m2);
      await r.rawOffer(id: 't5', attempt: 'aM3', to: m3);
      await pumpEventQueue(times: 60);
      expect(r.routeCount, 2);

      await r.rig.remotes[0].sendFileCancel('t5', attemptId: 'aM2');
      await pumpEventQueue(times: 40);
      expect(r.memberEvents[1], ['cancel:b:aM2']);
      expect(r.memberEvents[2], isEmpty);
      expect(r.routeCount, 1);

      await r.rig.remotes[2].sendFileCancel('t5', attemptId: 'aM3');
      await pumpEventQueue(times: 40);
      expect(r.senderEvents, ['cancel:d:aM3']);
      expect(r.routeCount, 0);
    },
  );

  test('an offer that points at another machine is refused', () async {
    await r.rawOffer(id: 't6', attempt: 'a1', to: m2, host: '192.168.1.99');
    await pumpEventQueue(times: 60);
    expect(r.copyAt(1, 't6'), isNull);
    expect(r.routeCount, 0);
    expect(r.senderEvents, ['cancel:c:a1'], reason: 'the sender is told');
  });

  test('members cannot send undirected or self-addressed offers', () async {
    await r.rawOffer(id: 't7', attempt: 'a1');
    await r.rawOffer(id: 't8', attempt: 'a1', to: m1);
    await pumpEventQueue(times: 60);
    for (final id in <String>['t7', 't8']) {
      expect(r.hostCopy(id), isNull);
      expect(r.copyAt(1, id), isNull);
      expect(r.copyAt(2, id), isNull);
    }
    expect(r.routeCount, 0);
    // 대상이 없는 offer는 알릴 수신자가 없어 조용히 버려지고, 자기 자신 대상은 접힘을 알림
    expect(r.senderEvents, ['cancel:b:a1']);
  });

  test('a second member cannot re-use the attempt of a routed offer', () async {
    await r.rawOffer(id: 't9', attempt: 'aX', to: m2);
    await pumpEventQueue(times: 60);
    await r.rawOffer(
      id: 't9',
      attempt: 'aX',
      to: m2,
      host: '192.168.1.13',
      link: 2,
    );
    await pumpEventQueue(times: 60);
    final copy = r.copyAt(1, 't9')!;
    expect(copy.srcHost, '192.168.1.11', reason: 'still the first sender');
    expect(copy.senderPeerId, m1);
    expect(r.routeCount, 1);
    expect(r.memberEvents[2], ['cancel:c:aX'], reason: 'the intruder is told');
    expect(r.senderEvents, isEmpty, reason: 'the real sender is not disturbed');
  });
}
