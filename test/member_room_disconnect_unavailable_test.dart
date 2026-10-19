import 'package:flutter_test/flutter_test.dart';

import 'support/member_room_rig.dart';

void main() {
  test(
    'target disconnect fails its offer even when roster callback is lost',
    () async {
      final r = await MemberRoomRig.create();
      final transfer = await r.offer();
      final target = MemberRoomRig.memberId(1);
      final other = MemberRoomRig.memberId(2);
      final attempt = r.sender
          .debugRecipients(transfer.id)
          .singleWhere((recipient) => recipient.key == target)
          .attemptId;
      expect(r.phases(transfer.id)[target], 'offered');

      r.rig.remotes[0].onRoomRoster = (_) {}; // 발신자의 명단 기반 실패 처리 누락
      await r.rig.remotes[1].close();
      await r.until(() => r.phases(transfer.id)[target] == 'failed');

      expect(r.senderEvents, ['unavailable:c:$attempt']);
      expect(r.phases(transfer.id)[target], 'failed');
      expect(r.phases(transfer.id)[other], 'offered');
      expect(r.routeCount, 1);
    },
  );

  test('an undeliverable room roster closes that member link', () async {
    final r = await MemberRoomRig.create();
    final senderLink = r.hostLinkOf(0);
    await r.faults.sessions.poison(0);

    await r.rig.remotes[1].close();
    await r.until(() => senderLink.isClosed);

    expect(senderLink.isClosed, isTrue);
    await r.until(() => r.rig.remotes[0].isClosed);
    expect(r.rig.remotes[0].isClosed, isTrue);
  });
}
