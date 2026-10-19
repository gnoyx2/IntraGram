import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

// 호스트가 방 멤버 사이로 중계한 파일 제어 프레임의 전달 결과를 봄: 나가면
// 그대로 끝, 못 나가면(false, 열린 링크의 봉인 예외) 받을 링크를 닫아
// 링크 종료 정리가 전송을 실패로 돌림 (offered/transferring에 영영
// 안 남고, 처리 안 된 비동기 오류도 없고, 그 링크와 무관한 경로는 그대로)
void main() {
  final m1 = MemberRoomRig.memberId(0);
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);

  late MemberRoomRig r;
  late FileTransfer t;

  String attemptOf(String key) => r.sender
      .debugRecipients(t.id)
      .singleWhere((recipient) => recipient.key == key)
      .attemptId;

  bool isOpen(int i) => r.rig.registry
      .linksForTransfer(r.rig.registry.appRoomId!)
      .any((link) => link.remotePeerId == MemberRoomRig.memberId(i));

  setUp(() async {
    r = await MemberRoomRig.create();
    t = await r.offer(); // M1이 낸 전송: 경로 (t, M2)·(t, M3)
    expect(r.routeCount, 2);
  });

  // M2가 M3에게 내는 별개 전송의 경로 (M1의 링크와 무관): 그 accept가 M2에 닿았는지 got에 남김
  Future<List<String>> routeM2toM3() async {
    final got = <String>[];
    r.rig.remotes[1].onFileAccepted = (id, at, token, actor) =>
        got.add('$id:$at');
    await r.rawOffer(
      id: 'x',
      attempt: 'ax',
      to: m3,
      host: '192.168.1.12',
      link: 1,
    );
    await pumpEventQueue(times: 60);
    return got;
  }

  // M3가 M1에게 내는 별개 전송의 경로 (M2의 링크와 무관)
  Future<void> routeM3toM1() async {
    await r.rawOffer(
      id: 'y',
      attempt: 'ay',
      to: m1,
      host: '192.168.1.13',
      link: 2,
    );
    await pumpEventQueue(times: 60);
  }

  test(
    'a delivered terminal frame reaches the sender and ends only its route',
    () async {
      await routeM2toM3();
      final at2 = attemptOf(m2);

      await r.rig.remotes[1].sendFileReject(t.id, attemptId: at2);
      await pumpEventQueue(times: 60);

      expect(r.senderEvents, ['reject:c:$at2']);
      expect(r.phases(t.id)[m2], 'rejected');
      expect(r.routeCount, 2, reason: '(t, M3) and (x, M3) stay');
      expect(isOpen(0) && isOpen(1) && isOpen(2), isTrue);

      final at3 = attemptOf(m3);
      await r.rig.remotes[2].sendFileAccept(
        t.id,
        attemptId: at3,
        pushToken: 'p',
      );
      await pumpEventQueue(times: 60);
      expect(r.senderEvents.last, 'accept:d:$at3');
    },
  );

  group('a frame that cannot be delivered closes the link it was for', () {
    // M1(보내는 쪽)의 호스트 쪽 링크만 닫히고 그 링크와 무관한 경로(M2->M3)는 그대로 동작함
    Future<void> expectOnlySenderLinkClosed(
      PeerLink senderLink,
      List<String> got,
    ) async {
      await r.until(() => senderLink.isClosed);
      await r.until(() => r.rig.remotes[0].isClosed);
      await pumpEventQueue(times: 60);
      expect(senderLink.isClosed, isTrue);
      expect(r.senderEvents, isEmpty, reason: 'nothing was delivered');
      expect(isOpen(1) && isOpen(2), isTrue, reason: 'M2 and M3 stay');
      expect(r.routeCount, 1, reason: 'only the unrelated (x, M3) is left');

      await r.rig.remotes[2].sendFileAccept(
        'x',
        attemptId: 'ax',
        pushToken: 'p',
      );
      await pumpEventQueue(times: 60);
      expect(got, ['x:ax'], reason: 'the unrelated route still works');
    }

    test('sendRawInner returns false (the socket write fails)', () async {
      final got = await routeM2toM3();
      final senderLink = r.hostLinkOf(0);
      r.faults.hostChannels[0].failAdds = true;

      await r.rig.remotes[1].sendFileReject(t.id, attemptId: attemptOf(m2));
      await expectOnlySenderLinkClosed(senderLink, got);
    });

    // false인데 링크는 스스로 안 닫히는 경우(보낼 큐가 가득 참):
    // 옛 코드는 프레임을 조용히 버려서 발신자가 offered로 남았음
    // 큐를 채우는 것과 중계를 같은 동기 구간에서 해서 결정적으로 만듦
    test('a full send queue is undelivered and the link is closed', () async {
      final got = await routeM2toM3();
      final senderLink = r.hostLinkOf(0);
      final pad = <String, dynamic>{
        'k': 'typing',
        'on': true,
        'pad': 'x' * (kMaxPendingOutboundBytes - 120), // 큐 바이트 한도 직전까지
      };
      unawaited(senderLink.sendRawInner(pad));

      // M2의 reject를 호스트가 중계하는 진입점을 그대로 호출: 이미 찬 M1 큐에는 더 못 실림
      r.hostLinkOf(1).onRoomFrame!(<String, dynamic>{
        'k': 'file_reject',
        'id': t.id,
        'at': attemptOf(m2),
        'from': 'peer1',
        'pid': m2,
      });

      await expectOnlySenderLinkClosed(senderLink, got);
    });

    test('an open link whose seal throws counts the same', () async {
      final got = await routeM2toM3();
      final senderLink = r.hostLinkOf(0);
      await r.faults.sessions.poison(0);

      await r.rig.remotes[1].sendFileReject(t.id, attemptId: attemptOf(m2));
      await expectOnlySenderLinkClosed(senderLink, got);
    });

    test(
      'the receiving side of a cancel is closed, not the canceller',
      () async {
        await routeM3toM1();
        final targetLink = r.hostLinkOf(1);
        await r.faults.sessions.poison(1); // 호스트→M2 봉인이 던짐

        await r.rig.remotes[0].sendFileCancel(t.id, attemptId: attemptOf(m2));
        await r.until(() => targetLink.isClosed);
        await pumpEventQueue(times: 60);

        expect(targetLink.isClosed, isTrue);
        expect(isOpen(0) && isOpen(2), isTrue, reason: 'M1 and M3 stay');
        expect(r.routeCount, 2, reason: '(t, M3) and (y, M1) are untouched');
        await r.rig.remotes[2].sendFileAccept(
          t.id,
          attemptId: attemptOf(m3),
          pushToken: 'p',
        );
        await pumpEventQueue(times: 60);
        expect(r.senderEvents, ['accept:d:${attemptOf(m3)}']);
      },
    );
  });

  test(
    'a link that is already closing drops the frame without an error',
    () async {
      await routeM2toM3();
      final gate = r.faults.hostChannels[2].closeGate = Completer<void>();
      unawaited(r.hostLinkOf(2).close()); // M3: isClosed지만 종료 정리는 아직
      await pumpEventQueue(times: 20);

      await r.rig.remotes[0].sendFileCancel(t.id, attemptId: attemptOf(m3));
      await pumpEventQueue(times: 60);
      expect(
        r.memberEvents[2],
        isEmpty,
        reason: 'undelivered to the closing link',
      );
      expect(r.routeCount, 3, reason: 'a dropped frame removes nothing');

      await r.rig.remotes[1].sendFileReject(t.id, attemptId: attemptOf(m2));
      await pumpEventQueue(times: 60);
      expect(r.senderEvents, [
        'reject:c:${attemptOf(m2)}',
      ], reason: 'others flow');

      gate.complete(); // 이제 종료 정리가 돌아 M3 몫 경로가 지워지고 명단이 갱신됨
      await r.until(() => r.phases(t.id)[m3] == 'failed');
      expect(r.routeCount, 0);
      expect(
        r.phases(t.id)[m3],
        'failed',
        reason: 'the sender learns even if the roster is missed',
      );
    },
  );

  // 소켓 쓰기 실패와 봉인 실패는 같게 끝남: 봉인 실패는 그 번호를 태워서 M2가 다음 프레임을
  // '빠진 프레임'으로 보고 어차피 링크를 닫으니 바로 닫음
  group('an offer the host cannot write to a live target', () {
    for (final (fault, breakIt) in <(String, Future<void> Function())>[
      (
        'the socket write fails',
        () async {
          r.faults.hostChannels[1].failAdds = true;
        },
      ),
      ('the seal throws', () => r.faults.sessions.poison(1)),
    ]) {
      test('$fault: the sender is told, no route stays', () async {
        await breakIt();
        await r.rawOffer(id: 'o1', attempt: 'a1', to: m2);
        await r.until(() => r.senderEvents.isNotEmpty);
        await pumpEventQueue(times: 60);

        expect(
          r.senderEvents,
          containsAll(['unavailable:c:a1', 'unavailable:c:${attemptOf(m2)}']),
        );
        expect(r.senderEvents, hasLength(2));
        expect(r.phases(t.id)[m2], 'failed');
        expect(r.routeCount, 1, reason: '(t, M2) went with M2\'s closed link');
        expect(isOpen(1), isFalse, reason: 'the link to M2 closes');
      });
    }
  });
}
