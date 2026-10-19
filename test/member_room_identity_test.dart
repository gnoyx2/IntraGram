import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';

import 'package:intragram/network/peer_link.dart';

import 'support/member_room_rig.dart';
import 'support/scripted_peer.dart';
import 'support/test_identities.dart';

// 방 멤버의 peerId는 mDNS와 방 명단으로 누구에게나 알려져 있음: 그걸 주장만 해서는 그 멤버 몫의 offer·
// 토큰·방 메시지를 받을 수 없어야 하고(키가 없으면 핸드셰이크에서 거부됨), 진짜 멤버가 다시 붙으면
// 옛 링크를 대신함
void main() {
  final m2 = MemberRoomRig.memberId(1);
  late MemberRoomRig r;
  setUp(() async => r = await MemberRoomRig.create());

  Future<ScriptedPeer> attacker() async {
    final wire = StreamChannelController<dynamic>();
    await r.rig.registry.acceptInbound(
      wire.foreign,
      remoteHost: '192.168.1.66',
      remotePort: 5555,
    );
    return ScriptedPeer.create(testIdentity('e'), wire.local);
  }

  test(
    'claiming a member peerId without its key never joins the room',
    () async {
      final roomId = r.rig.registry.appRoomId!;
      final memberCount = r.rig.store.conversation(roomId)!.memberCount;
      final peer = await attacker();
      // 멤버 M2의 peerId와 (공개된) 신원 키를 그대로 주장하지만 서명은 자기 키(e)로 함
      final memberKey = testIdentity('c').publicKey;
      peer.sendDialerHello(peerId: m2, claimedKey: memberKey);
      await pumpEventQueue(times: 80);
      await peer.completeHandshake();
      peer.sendAuth(await peer.proof(asDialer: true, ownKey: memberKey));
      await pumpEventQueue(times: 100);

      final room = r.rig.store.conversation(roomId)!;
      expect(room.memberCount, memberCount, reason: 'the room did not grow');
      expect(
        room.members[m2]?.alias,
        'peer1',
        reason: 'the member entry is untouched',
      );
      expect(
        r.rig.remotes[1].isClosed,
        isFalse,
        reason: 'M2 was not displaced',
      );
      expect(
        peer.frames.where((f) => f['t'] == 'enc'),
        isEmpty,
        reason: 'nothing encrypted (room join, offers) was ever sent to it',
      );

      final t = await r.offer();
      expect(
        r.copyAt(1, t.id),
        isNotNull,
        reason: 'the real M2 gets the offer',
      );
      expect(peer.frames.where((f) => f['t'] == 'enc'), isEmpty);
    },
  );

  test('a member that reconnects with its key replaces its old link', () async {
    final t = await r.offer();
    final attempt = r.copyAt(1, t.id)!.attemptId!;
    final again = await r.reconnect(1, host: '192.168.1.99');
    await pumpEventQueue(times: 100);

    expect(
      r.rig.remotes[1].isClosed,
      isTrue,
      reason: 'the old link was closed',
    );
    expect(again.link.isClosed, isFalse);
    final room = r.rig.store.conversation(r.rig.registry.appRoomId!)!;
    expect(room.memberCount, 4);
    expect(room.members[m2]?.online, isTrue);
    expect(
      r.routeCount,
      2,
      reason: 'the in-flight routes moved to the new link',
    );

    await again.link.sendFileAccept(t.id, attemptId: attempt, pushToken: 'x');
    await pumpEventQueue(times: 60);
    expect(r.senderEvents, ['accept:c:$attempt']);
  });
}
