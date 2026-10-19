import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';

import 'support/admission_rig.dart';

// 미인증 동시 접속 상한은 세션을 만드는 동안(아직 링크로 등록 전)의 접속도
// 세야 함: 한꺼번에 들어온 접속이 전부 상한 검사를 통과해 등록되던 결함
// (같은 host 6개가 상한 4를 넘어 전부 등록됨)의 회귀 (세션 생성을 붙잡고 보는
// 경우는 link_registry_admission_creation_test.dart)
void main() {
  late AdmissionRig rig;
  setUp(() => rig = AdmissionRig.create());

  test(
    'six simultaneous connections from one host keep only its share',
    () async {
      final result = await rig.flood(['192.168.1.66'], each: 6);

      expect(result.kept, kMaxPendingHandshakesPerHost);
      expect(result.refused, 2);
      expect(rig.store.conversations, hasLength(kMaxPendingHandshakesPerHost));
      expect(
        rig.registry.debugInboundReservations,
        0,
        reason: 'no slot leaked',
      );
    },
  );

  test(
    'simultaneous connections from many hosts stop at the overall cap',
    () async {
      final hosts = [for (var i = 0; i < 20; i++) '192.168.1.${100 + i}'];
      final result = await rig.flood(hosts, each: 1);

      expect(result.kept, kMaxPendingHandshakes);
      expect(result.refused, 4);
      expect(rig.store.conversations, hasLength(kMaxPendingHandshakes));
      expect(rig.registry.debugInboundReservations, 0);
    },
  );

  test('both caps hold together when several hosts flood at once', () async {
    final hosts = [for (var i = 0; i < 5; i++) '192.168.1.${100 + i}'];
    final result = await rig.flood(
      hosts,
      each: 6,
    ); // 호스트별 4 → 20이 후보, 전체 상한은 16

    expect(result.kept, kMaxPendingHandshakes);
    expect(rig.store.conversations, hasLength(kMaxPendingHandshakes));
    for (final host in hosts) {
      expect(
        rig.store.conversations.where((c) => c.peerHost == host).length,
        lessThanOrEqualTo(kMaxPendingHandshakesPerHost),
        reason: host,
      );
    }
  });

  test(
    'a connection after dispose is closed without a tile or a slot',
    () async {
      await rig.registry.disposeAll();
      final conn = rig.connect('192.168.1.66', 5000);
      await conn.accepted;
      await pumpEventQueue();

      expect(conn.closed(), isTrue);
      expect(rig.store.conversations, isEmpty);
      expect(rig.registry.debugInboundReservations, 0);
    },
  );
}
