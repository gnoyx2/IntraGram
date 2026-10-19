import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';

import 'support/member_room_rig.dart';

// 방 안 전송 id의 임자: 먼저 쓴 쪽이 임자라서, 다른 멤버가 같은 id로 다른 수신자한테 먼저 offer해
// 그 수신자가 id를 자기한테 묶게 만드는 선점은 호스트가 막음. 경로 상한을 넘어 밀려난 경로의
// 발신자는 통지를 받음
void main() {
  final m2 = MemberRoomRig.memberId(1);
  final m3 = MemberRoomRig.memberId(2);
  late MemberRoomRig r;
  setUp(() async => r = await MemberRoomRig.create());

  Future<void> squat(String id, {required String to}) => r.rawOffer(
    id: id,
    attempt: 'aX',
    to: to,
    host: '192.168.1.13', // M3의 링크 주소
    link: 2,
  );

  test('the id a member already offered to the host cannot be taken', () async {
    await r.rawOffer(id: 'own1', attempt: 'aH', to: r.hostId);
    await r.rawOffer(id: 'own1', attempt: 'aM3', to: m3);
    await pumpEventQueue(times: 60);
    await r.rig.remotes[2].sendFileReject('own1', attemptId: 'aM3');
    await pumpEventQueue(times: 40);
    expect(r.routeCount, 0, reason: 'M3 rejected, no live route is left');

    await squat('own1', to: m2);
    await pumpEventQueue(times: 60);
    expect(r.copyAt(1, 'own1'), isNull);
    expect(r.routeCount, 0);
    expect(r.hostCopy('own1')?.senderPeerId, MemberRoomRig.memberId(0));
  });

  test(
    'the id of a live routed transfer cannot be offered to others',
    () async {
      await r.rawOffer(id: 'own2', attempt: 'aM3', to: m3);
      await pumpEventQueue(times: 60);
      expect(r.hostCopy('own2'), isNull, reason: 'the host holds no record');

      await squat('own2', to: m2);
      await pumpEventQueue(times: 60);
      expect(r.copyAt(1, 'own2'), isNull);
      expect(r.routeCount, 1, reason: "the owner's route is untouched");
      expect(r.copyAt(2, 'own2')?.attemptId, 'aM3');
    },
  );

  test('the owner can still add recipients and re-offer', () async {
    await r.rawOffer(id: 'own3', attempt: 'aM3', to: m3);
    await r.rawOffer(id: 'own3', attempt: 'aM2', to: m2);
    await r.rawOffer(id: 'own3', attempt: 'aM2b', to: m2);
    await pumpEventQueue(times: 80);
    expect(r.copyAt(2, 'own3')?.attemptId, 'aM3');
    expect(r.copyAt(1, 'own3')?.attemptId, 'aM2b');
    expect(r.routeCount, 2);
  });

  test('the id of a transfer the host offered cannot be taken', () async {
    final registry = r.rig.registry;
    registry.localEndpoint = (host: '192.168.1.10', port: 7890);
    await registry.offerInlineBytes(
      registry.appRoomId!,
      'host.bin',
      Uint8List(8),
    );
    await pumpEventQueue(times: 80);
    final hostTransfer = r.rig.store.transfers.single;
    final before = r.copyAt(1, hostTransfer.id)!;

    await squat(hostTransfer.id, to: m2);
    await pumpEventQueue(times: 60);
    expect(r.copyAt(1, hostTransfer.id)?.attemptId, before.attemptId);
    expect(r.copyAt(1, hostTransfer.id)?.senderPeerId, r.hostId);
    expect(r.routeCount, 0);
  });

  test('a route dropped at the cap is reported to its sender', () async {
    r.rig.registry.debugMaxRoomFileRoutesPerSender = 2;
    await r.rawOffer(id: 'e1', attempt: 'a1', to: m2);
    await r.rawOffer(id: 'e2', attempt: 'a2', to: m2);
    await pumpEventQueue(times: 60);
    expect(r.routeCount, 2);
    expect(r.senderEvents, isEmpty);

    await r.rawOffer(id: 'e3', attempt: 'a3', to: m2);
    await pumpEventQueue(times: 60);
    expect(r.routeCount, 2);
    expect(r.senderEvents, ['cancel:c:a1'], reason: 'the oldest one is told');

    // 밀려난 경로는 더는 중계하지 않음
    r.senderEvents.clear();
    await r.rig.remotes[1].sendFileAccept(
      'e1',
      attemptId: 'a1',
      pushToken: 'x',
    );
    await pumpEventQueue(times: 40);
    expect(r.senderEvents, isEmpty);
    await r.rig.remotes[1].sendFileAccept(
      'e3',
      attemptId: 'a3',
      pushToken: 'x',
    );
    await pumpEventQueue(times: 40);
    expect(r.senderEvents, ['accept:c:a3']);
  });
}
