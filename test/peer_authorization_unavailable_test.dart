import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/peer_auth_rig.dart';

// `file_unavailable`의 인가: 이 링크의 상대가 그 방의 *확정된* 호스트이고 내 아웃고잉 전송을 가리킬 때만
// 콜백까지 가고, 그 외(1:1 상대, 방 멤버, 내가 호스트인 링크, 다른 대화·수신 전송·모르는 id)는 기본 거부이며
// 다른 멤버한테 중계되지도 않음. 수신자·attempt 검사는 registry(member_room_unavailable_test)가 함
void main() {
  late AuthRig rig;
  final calls = <String>[];
  final frame = InnerFrame.fileUnavailable(
    'o1',
    attempt: 'a1',
    target: 'peerX',
  );

  setUp(() async {
    rig = await AuthRig.create();
    calls.clear();
    rig.linkA.onFileUnavailable = (id, at, target) =>
        calls.add('$id:$at:$target');
    rig.linkB.onFileUnavailable = (id, at, target) =>
        calls.add('B:$id:$at:$target');
    rig.storeA.upsertTransfer(
      authTransfer('o1', 'cA', TransferDirection.outgoing),
    );
  });

  // B가 A를 자기 방(호스트)에 합류시킴: A 입장에서 B가 확정된 호스트가 됨
  Future<void> joinAsMemberOfB() async {
    await rig.linkB.sendRawInner(<String, dynamic>{
      'k': 'room_join',
      'count': 2,
    });
    await pumpEventQueue(times: 60);
  }

  Future<void> hostSends([Map<String, dynamic>? wire]) async {
    await rig.linkB.sendRawInner(wire ?? frame);
    await pumpEventQueue(times: 60);
  }

  test('the confirmed host of our room reaches the callback', () async {
    await joinAsMemberOfB();
    expect(rig.storeA.conversation('cA')!.isRoom, isTrue);
    await hostSends();
    expect(calls, ['o1:a1:peerX']);
  });

  test('a plain 1:1 peer cannot send it', () async {
    await hostSends();
    expect(calls, isEmpty);
  });

  test(
    'a peer that is not the confirmed host of the room cannot send it',
    () async {
      rig.storeA.updateConversation(
        'cA',
        (c) => c.copyWith(
          isRoom: true,
          hostAlias: 'real-host',
          hostPeerId: 'x' * 32,
        ),
      );
      await joinAsMemberOfB(); // B의 room_join은 거부됨 → 역할이 host가 안 됨
      await hostSends();
      expect(calls, isEmpty);
    },
  );

  test(
    'an incoming transfer, another conversation or an unknown id is dropped',
    () async {
      await joinAsMemberOfB();
      rig.storeA
        ..upsertConversation(conv('other', 'someone'))
        ..upsertTransfer(authTransfer('i1', 'cA', TransferDirection.incoming))
        ..upsertTransfer(
          authTransfer('o2', 'other', TransferDirection.outgoing),
        );
      for (final id in <String>['i1', 'o2', 'ghost']) {
        await hostSends(
          InnerFrame.fileUnavailable(id, attempt: 'a1', target: 'peerX'),
        );
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'a member of a room we host cannot send it, and it is never relayed',
    () async {
      rig.linkB.markHostedMember(); // B가 호스트, A는 B의 멤버
      rig.storeB.upsertTransfer(
        authTransfer('o1', 'cB', TransferDirection.outgoing),
      );
      await rig.sendFromA(frame);

      expect(calls, isEmpty, reason: 'the host never obeys a member');
      expect(rig.relayed, isEmpty, reason: 'and never passes it to others');
    },
  );

  test('malformed notices are dropped before the callback', () async {
    await joinAsMemberOfB();
    await hostSends(<String, dynamic>{
      'k': 'file_unavailable',
      'id': 'o1',
      'at': 'a1',
    });
    await hostSends(<String, dynamic>{
      'k': 'file_unavailable',
      'id': 'o1',
      'at': 'a1',
      'to': 'bad target',
    });
    expect(calls, isEmpty);
  });
}
