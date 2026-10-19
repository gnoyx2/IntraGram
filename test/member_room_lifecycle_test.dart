import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/network_guard.dart' show SecurityException;
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

// 방 멤버가 낸 파일이 여러 수신자한테 독립적으로 흐르는지: 토큰·ACK·실패/재시도·취소·
// 멤버 이탈과 복귀(명단·정직한 실패는 member_room_delivery_test.dart)
void main() {
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);

  test(
    'recipients have their own single-use tokens and one ACK never completes the group',
    () async {
      final r = await MemberRoomRig.create();
      final t = await r.offer();
      final host = r.hostCopy(t.id)!;
      final second = r.copyAt(1, t.id)!;
      final third = r.copyAt(2, t.id)!;
      expect({host.attemptId, second.attemptId, third.attemptId}, hasLength(3));
      expect({host.pullToken, second.pullToken, third.pullToken}, hasLength(3));

      await r.receiveAsMember(1, t.id);
      expect(r.phases(t.id), {
        r.hostId: 'offered',
        m2: 'complete',
        m3: 'offered',
      });
      expect(
        r.senderStore.transfer(t.id)!.state,
        isNot(TransferState.complete),
      );
      expect(r.routeCount, 1, reason: 'the finished attempt route is gone');

      Future<Object?> spend(String attempt, String token) =>
          r.sender.openDownload(
            transferId: t.id,
            attemptId: attempt,
            token: token,
            declaredSize: t.totalBytes,
          );
      await expectLater(
        spend(second.attemptId!, second.pullToken!),
        throwsA(isA<SecurityException>()),
        reason: 'a token is single-use',
      );
      await expectLater(
        spend(second.attemptId!, third.pullToken!),
        throwsA(isA<SecurityException>()),
        reason: "a token does not open another recipient's attempt",
      );
      await expectLater(
        spend(third.attemptId!, second.pullToken!),
        throwsA(isA<SecurityException>()),
      );

      await r.receiveAsMember(2, t.id); // 틀린 attempt 시도가 M3 토큰을 태우지 않음
      expect(
        r.senderStore.transfer(t.id)!.state,
        isNot(TransferState.complete),
      );
      await r.receiveAsHost(t.id);
      expect(r.senderStore.transfer(t.id)!.state, TransferState.complete);
      expect(r.routeCount, 0);
    },
  );

  test(
    'a failed recipient retries alone while the completed one stays complete',
    () async {
      final r = await MemberRoomRig.create();
      final t = await r.offer();
      await r.receiveAsMember(2, t.id);
      final third = r.copyAt(2, t.id)!;
      final first = r.copyAt(1, t.id)!;
      await r.rig.remotes[1].sendFileAccept(
        t.id,
        attemptId: first.attemptId!,
        pushToken: 'x',
      );
      await pumpEventQueue(times: 40);
      final download = (await r.sender.openDownload(
        transferId: t.id,
        attemptId: first.attemptId!,
        token: first.pullToken!,
        declaredSize: t.totalBytes,
      ))!;
      await download.body.listen((_) {}).cancel(); // M2의 GET이 중간에 끊김
      await pumpEventQueue(times: 40);
      expect(r.phases(t.id)[m2], 'failed');
      expect(r.phases(t.id)[m3], 'complete');

      await r.rig.remotes[1].sendFileRetry(t.id, attemptId: first.attemptId!);
      await pumpEventQueue(times: 80);
      final retried = r.copyAt(1, t.id)!;
      expect(retried.attemptId, isNot(first.attemptId));
      expect(retried.pullToken, isNot(first.pullToken));
      expect(r.phases(t.id), {
        r.hostId: 'offered',
        m2: 'offered',
        m3: 'complete',
      });
      expect(
        r.copyAt(2, t.id)!.attemptId,
        third.attemptId,
        reason: 'M3 untouched',
      );
      await expectLater(
        r.sender.openDownload(
          transferId: t.id,
          attemptId: first.attemptId!,
          token: first.pullToken!,
          declaredSize: t.totalBytes,
        ),
        throwsA(isA<SecurityException>()),
        reason: 'the old attempt and token are dead',
      );

      await r.receiveAsMember(1, t.id);
      expect(r.phases(t.id)[m2], 'complete');
      expect(r.phases(t.id)[m3], 'complete');
    },
  );

  test(
    'cancelling the transfer ends every route and cancels every copy',
    () async {
      final r = await MemberRoomRig.create();
      final t = await r.offer();
      expect(r.routeCount, 2);

      r.sender.cancelTransfer(t.id);
      await pumpEventQueue(times: 80);

      expect(r.routeCount, 0);
      expect(r.memberEvents[1], hasLength(1));
      expect(r.memberEvents[2], hasLength(1));
      expect(r.hostCopy(t.id)!.state, TransferState.cancelled);
      expect(r.senderStore.transfer(t.id)!.state, TransferState.cancelled);
    },
  );

  test('the sender leaving drops every route it owned', () async {
    final r = await MemberRoomRig.create();
    await r.offer();
    expect(r.routeCount, 2);

    await r.rig.remotes[0].close();
    await pumpEventQueue(times: 100);

    expect(r.routeCount, 0);
  });

  test(
    'a member that leaves fails only its recipient and can be retried after it returns',
    () async {
      final r = await MemberRoomRig.create();
      final t = await r.offer();
      await r.rig.remotes[1].close();
      await pumpEventQueue(times: 100);
      expect(r.phases(t.id), {
        r.hostId: 'offered',
        m2: 'failed',
        m3: 'offered',
      });
      expect(r.routeCount, 1, reason: "only M3's route is left");

      await r.receiveAsHost(t.id);
      await r.receiveAsMember(2, t.id);
      expect(r.senderStore.transfer(t.id)!.state, TransferState.failed);
      await r.sender.retryTransfer(t.id);
      await pumpEventQueue(times: 60);
      expect(r.phases(t.id)[m2], 'failed', reason: 'M2 is out of the room');

      final back = await r.reconnect(1);
      await r.sender.retryTransfer(t.id);
      await pumpEventQueue(times: 80);
      expect(r.phases(t.id)[m2], 'offered');
      expect(back.store.transfer(t.id)?.attemptId, isNotNull);
      expect(r.phases(t.id)[m3], 'complete');
    },
  );
}
