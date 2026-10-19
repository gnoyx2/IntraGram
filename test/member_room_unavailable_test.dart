import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

// 호스트가 못 찾는 수신자(막 나간 멤버, 닫히는 링크)한테 가는 offer: 호스트가 `file_unavailable`로 발신자에게
// 알려서 그 수신자가 영영 offered에 남지 않음. 수신자의 취소(`file_cancel`)로 위장하지 않고, 방 호스트만
// 보낼 수 있으며, 발신자는 등록된 수신자·현재 attempt일 때만 그 수신자를 재시도 가능한 failed로 돌림
void main() {
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);
  final missing = 'z' * 32; // 방에 없는 peerId

  // 발신자(M1)가 [key] 수신자한테 낸 현재 attempt
  String attemptOf(MemberRoomRig r, String id, String key) =>
      r.sender.debugRecipients(id).singleWhere((x) => x.key == key).attemptId;

  group('an offer to a recipient the host cannot find', () {
    test('is answered with file_unavailable, never with a cancel', () async {
      final r = await MemberRoomRig.create();
      await r.rig.remotes[2].close(); // M3가 나감
      await pumpEventQueue(times: 100);

      await r.rawOffer(id: 'u1', attempt: 'a1', to: m3);
      await r.until(() => r.senderEvents.isNotEmpty);

      expect(r.senderEvents, ['unavailable:d:a1']);
      expect(r.routeCount, 0, reason: 'no route for an offer nobody got');
      expect(r.copyAt(2, 'u1'), isNull);
    });

    test('a target that is mid-shutdown counts as missing', () async {
      final r = await MemberRoomRig.create();
      final gate = r.faults.hostChannels[2].closeGate = Completer<void>();
      unawaited(r.hostLinkOf(2).close()); // 호스트 쪽 M3 링크: isClosed지만 종료 정리는 아직
      await pumpEventQueue(times: 20);

      await r.rawOffer(id: 'c1', attempt: 'a1', to: m3);
      await r.until(() => r.senderEvents.isNotEmpty);

      expect(r.senderEvents, ['unavailable:d:a1']);
      expect(r.routeCount, 0);
      gate.complete();
      await pumpEventQueue(times: 60);
    });

    test(
      'leaves the real sender no recipient stuck offered, and it can retry',
      () async {
        final r = await MemberRoomRig.create();
        final everyone = r.senderStore
            .conversation(MemberRoomRig.roomId)!
            .roomRecipientIds;
        await r.rig.remotes[2].close(); // M3가 나가고 발신자의 명단도 따라 줄어듦
        await pumpEventQueue(times: 100);
        // 발신자가 명단 스냅샷을 뜬 뒤에야 갱신이 오는 경합을 흉내: 스냅샷엔 아직 M3가 있음
        r.senderStore.updateConversation(
          MemberRoomRig.roomId,
          (c) => c.copyWith(roomRecipientIds: everyone),
        );

        final t = await r.offer();
        await r.until(() => r.phases(t.id)[m3] != 'offered');

        expect(r.phases(t.id), {
          r.hostId: 'offered',
          m2: 'offered',
          m3: 'failed',
        });
        expect(r.senderEvents, hasLength(1));
        expect(r.senderEvents.single, startsWith('unavailable:d:'));

        // 나머지가 끝나면 전송은 failed(재시도 가능)이고, M3가 돌아오면 M3 몫만 다시 offer됨
        await r.receiveAsHost(t.id);
        await r.receiveAsMember(1, t.id);
        expect(r.senderStore.transfer(t.id)!.state, TransferState.failed);
        final back = await r.reconnect(2);
        await r.sender.retryTransfer(t.id);
        await r.until(() => back.store.transfer(t.id) != null);
        expect(r.phases(t.id)[m3], 'offered');
        expect(back.store.transfer(t.id)?.attemptId, attemptOf(r, t.id, m3));
      },
    );

    test(
      'a roster update in the middle of the offer loop cannot strand a recipient',
      () async {
        final r = await MemberRoomRig.create();
        final everyone = r.senderStore
            .conversation(MemberRoomRig.roomId)!
            .roomRecipientIds;
        final without = [
          for (final id in everyone)
            if (id != m3) id,
        ];
        await r.rig.remotes[2].close(); // 호스트는 이미 M3를 모름
        await pumpEventQueue(times: 100);
        r.senderStore.updateConversation(
          MemberRoomRig.roomId,
          (c) => c.copyWith(roomRecipientIds: everyone),
        );

        // 발신자가 두 번째 offer(M2 몫)를 써 낸 직후, M3 몫 수신자를 등록하기 전에 명단 갱신이 도착함
        final wire = r.faults.memberChannels[0]..adds = 0;
        wire.onAdd = (adds) {
          if (adds != 2) return;
          r.senderStore.updateConversation(
            MemberRoomRig.roomId,
            (c) => c.copyWith(roomRecipientIds: without),
          );
          r.sender.handleRoomRoster(MemberRoomRig.roomId, without);
        };

        final t = await r.offer();
        await r.until(() => r.phases(t.id)[m3] != 'offered');

        expect(r.phases(t.id)[m3], 'failed', reason: 'never offered forever');
        expect(r.phases(t.id)[m2], 'offered');
        expect(r.phases(t.id)[r.hostId], 'offered');
      },
    );
  });

  group(
    'the sender only trusts the room host, for a registered recipient and attempt',
    () {
      late MemberRoomRig r;
      late FileTransfer t;
      setUp(() async {
        r = await MemberRoomRig.create();
        t = await r.offer();
      });

      test(
        'a general member cannot forge it — nobody is told, nothing changes',
        () async {
          final at = attemptOf(r, t.id, m3);
          final forged = InnerFrame.fileUnavailable(
            t.id,
            attempt: at,
            target: m3,
          );
          await r.rig.remotes[1].sendRawInner(forged); // M2가 호스트인 척
          await r.rig.remotes[2].sendRawInner(forged);
          await pumpEventQueue(times: 80);

          expect(r.senderEvents, isEmpty);
          expect(
            r.memberEvents[2],
            isEmpty,
            reason: 'not relayed to other members',
          );
          expect(r.phases(t.id)[m3], 'offered');
          expect(r.routeCount, 2);
        },
      );

      test(
        'a stale attempt, an unknown recipient or a foreign id change nothing',
        () async {
          final at = attemptOf(r, t.id, m3);
          final host = r.hostLinkOf(0);
          await host.sendFileUnavailable(
            t.id,
            attemptId: 'stale',
            targetId: m3,
          );
          await host.sendFileUnavailable(
            t.id,
            attemptId: at,
            targetId: missing,
          );
          await host.sendFileUnavailable('ghost', attemptId: at, targetId: m3);
          await pumpEventQueue(times: 80);

          expect(r.phases(t.id)[m3], 'offered');
          expect(r.phases(t.id)[m2], 'offered');
          // 모르는 전송 id는 인가 단계에서 버려져 콜백에도 안 닿음(앞의 둘만 콜백까지 감)
          expect(r.senderEvents, hasLength(2));
        },
      );

      test('the right host notice fails only that recipient', () async {
        final at = attemptOf(r, t.id, m3);
        await r
            .hostLinkOf(0)
            .sendFileUnavailable(t.id, attemptId: at, targetId: m3);
        await pumpEventQueue(times: 80);

        expect(r.phases(t.id), {
          r.hostId: 'offered',
          m2: 'offered',
          m3: 'failed',
        });
      });

      test('a recipient that already finished stays finished', () async {
        await r.receiveAsMember(1, t.id);
        expect(r.phases(t.id)[m2], 'complete');

        await r
            .hostLinkOf(0)
            .sendFileUnavailable(
              t.id,
              attemptId: attemptOf(r, t.id, m2),
              targetId: m2,
            );
        await pumpEventQueue(times: 80);

        expect(r.phases(t.id)[m2], 'complete');
      });
    },
  );

  test(
    'a notice the host cannot send closes the link that could not take it',
    () async {
      final r = await MemberRoomRig.create();
      final senderLink = r.hostLinkOf(0);
      final others = [r.hostLinkOf(1), r.hostLinkOf(2)];
      await r.faults.sessions.poison(0); // 호스트→M1 송신은 이제 봉인에서 던짐

      await r.rawOffer(id: 'w1', attempt: 'a1', to: missing);
      await r.until(() => senderLink.isClosed);

      expect(senderLink.isClosed, isTrue, reason: 'the failure converges');
      await r.until(() => r.rig.remotes[0].isClosed);
      expect(r.rig.remotes[0].isClosed, isTrue, reason: 'the sender sees it');
      expect(r.senderEvents, isEmpty);
      expect(others.map((l) => l.isClosed), [false, false]);
    },
  );
}
