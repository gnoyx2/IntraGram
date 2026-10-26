import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart' show kMaxThumbBytes;
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

// 방 멤버가 낸 파일의 명단(수신자 목록)과 정직한 실패: 명단 갱신, 서버 주소·호스트 링크·
// 명단을 못 믿을 때의 실패, 상한 초과 썸네일 거부, 중복 링크 최신 우선, 표시 이름
void main() {
  final m1 = MemberRoomRig.memberId(0);
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);

  test(
    'the roster follows joins, leaves and reconnects without duplicates',
    () async {
      final r = await MemberRoomRig.create();
      List<String> rosterOf(int i) =>
          r.rig.remoteStores[i].conversation('remote$i')!.roomRecipientIds;
      final everyone = <String>{r.hostId, m1, m2, m3};
      for (var i = 0; i < 3; i++) {
        expect(rosterOf(i), hasLength(4));
        expect(rosterOf(i).toSet(), everyone);
      }

      await r.rig.remotes[2].close();
      await pumpEventQueue(times: 100);
      for (var i = 0; i < 2; i++) {
        expect(rosterOf(i).toSet(), everyone.difference({m3}));
      }

      await r.reconnect(2);
      for (var i = 0; i < 2; i++) {
        expect(rosterOf(i), hasLength(4));
        expect(rosterOf(i).toSet(), everyone);
      }

      // 같은 peerId의 링크가 하나 더 붙어도(옛 링크가 안 닫힌 재접속) 명단엔 한 번만
      final again = await r.reconnect(2, host: '192.168.1.99');
      for (var i = 0; i < 2; i++) {
        expect(rosterOf(i), hasLength(4));
      }
      expect(
        again.store.conversation('again2')!.roomRecipientIds,
        hasLength(4),
      );
    },
  );

  test(
    'a member without a local server fails the transfer and sends no offer',
    () async {
      final r = await MemberRoomRig.create(serverUp: false);
      final t = await r.offer();
      final sent = r.senderStore.transfer(t.id)!;
      expect(sent.state, TransferState.failed);
      expect(sent.error, 'network');
      expect(r.hostCopy(t.id), isNull);
      expect(r.copyAt(1, t.id), isNull);
      expect(r.copyAt(2, t.id), isNull);
    },
  );

  group('an unverifiable host link or roster fails the transfer', () {
    final broken = <String, Conversation Function(Conversation)>{
      'another peer is the confirmed host': (c) =>
          c.copyWith(hostPeerId: 'z' * 32),
      'no roster': (c) => c.copyWith(roomRecipientIds: <String>[]),
      'roster without the host': (c) =>
          c.copyWith(roomRecipientIds: <String>[m1, m2]),
    };
    broken.forEach((name, mutate) {
      test(name, () async {
        final r = await MemberRoomRig.create();
        r.senderStore.updateConversation(MemberRoomRig.roomId, mutate);
        final t = await r.offer();
        expect(r.senderStore.transfer(t.id)!.state, TransferState.failed);
        expect(r.hostCopy(t.id), isNull);
        expect(r.copyAt(1, t.id), isNull);
      });
    });
  });

  test(
    'an offer whose thumbnail is over the wire cap never reaches the member',
    () async {
      final r = await MemberRoomRig.create();
      // 수락 전 썸네일은 kMaxThumbBytes까지만 허용하며 초과 시 호스트가 파싱에서 버려 중계도 경로도 없음
      // (offer 중계 실패 자체는 member_room_offer_failure_test가 fault 주입으로 검증함)
      r.senderStore.largeMessageMode = LargeMessageMode.unlimited;
      await r.rawOffer(
        id: 'big',
        attempt: 'a1',
        to: m2,
        thumb: 'A' * ((kMaxThumbBytes + 2) ~/ 3 * 4 + 4),
      );
      await pumpEventQueue(times: 60);

      expect(r.copyAt(1, 'big'), isNull);
      expect(r.routeCount, 0);
      expect(r.hostLinkOf(1).isClosed, isFalse, reason: 'M2 never saw it');
    },
  );

  test(
    'replies to a member with two live links go to the newest one',
    () async {
      final r = await MemberRoomRig.create();
      await r.rawOffer(id: 'dup', attempt: 'aH', to: r.hostId);
      await pumpEventQueue(times: 40);
      final again = await r.reconnect(0, host: '192.168.1.99');
      final link = r.rig.registry.linkForIncomingTransfer(r.hostCopy('dup')!);
      expect(link?.remoteHost, '192.168.1.99');
      expect(again.link.isClosed, isFalse);
    },
  );

  test('relayed file messages carry the real sender name', () async {
    final r = await MemberRoomRig.create();
    final t = await r.offer();
    final rooms = [
      (r.rig.store, r.rig.registry.appRoomId!),
      (r.rig.remoteStores[1], 'remote1'),
      (r.rig.remoteStores[2], 'remote2'),
    ];
    for (final (store, roomId) in rooms) {
      final message = store
          .messages(roomId)
          .singleWhere((m) => m.transferId == t.id);
      expect(message.senderAlias, 'peer0');
    }
  });
}
