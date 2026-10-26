import 'package:flutter_test/flutter_test.dart';

import 'support/member_room_rig.dart';

// 1:1에서 승격된 방은 옛 상대 주소를 그대로 들고 있음. 멤버가 다 나간 뒤 호스트가 다시 걸면 그 링크가 방 자리에 끼어들어
// 멤버 코드 확인·방 파일이 엉뚱한 기기로 갔음. 내가 연 방은 다시 걸지 않고 멤버가 각자 다시 들어옴
void main() {
  final m2 = MemberRoomRig.memberId(1);
  late MemberRoomRig r;
  late String roomId;
  var dials = 0;

  setUp(() async {
    r = await MemberRoomRig.create(members: 2);
    roomId = r.rig.registry.appRoomId!;
    await r.rig.remotes[0].close();
    await r.rig.remotes[1].close();
    await pumpEventQueue(times: 200);
    expect(r.rig.store.conversation(roomId)!.online, isFalse);
    dials = 0;
    r.rig.registry.debugDial = (_) async {
      dials++;
      throw StateError('a hosted room must not dial');
    };
    await r.rig.registry.reconnect(roomId);
  });

  test('reconnecting a room this device hosts dials nobody', () {
    expect(dials, 0);
    expect(r.rig.registry.linksForTransfer(roomId), isEmpty);
  });

  test(
    'a code check after the room emptied reaches the member who came back',
    () async {
      final back = await r.reconnect(1);
      final sas = r.rig.store.conversation(roomId)!.members[m2]!.sas;
      expect(sas, isNotNull);
      r.rig.registry.markRoomMemberVerified(roomId, m2, expectedSas: sas);
      await pumpEventQueue(times: 60);
      expect(
        back.store.conversation('again1')!.members[r.hostId]?.peerVerified,
        isTrue,
      );
      expect(r.rig.registry.linksForTransfer(roomId), [r.hostLinkOf(1)]);
    },
  );
}
