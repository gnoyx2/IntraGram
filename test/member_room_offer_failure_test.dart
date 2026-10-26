import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

// 호스트의 방 파일 중계 경계 케이스: 이미 닫히는 중인 링크로는 오류 없이 프레임을 버린 뒤 종료 정리에서
// 실패 처리하고, 살아있는 대상 링크에 offer를 못 쓰면 발신자에게 file_unavailable을 알리고 대상 링크를 닫음

void main() {
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

  // M2가 M3에게 내는 별개 전송 경로를 세워 M1 링크와 무관한 경로 수를 함께 확인함
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
