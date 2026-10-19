import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/network/crypto_engine.dart';

import 'support/admission_rig.dart';

// 세션을 만드는 동안(첫 await 뒤, 링크로 등록되기 전)의 접속도
// 상한에 세어지고, 링크로 오르는 순간 예약을 돌려줘 이중으로 안 세며,
// 세션 생성 실패/dispose/상대의 끊김 어느 출구로 나가든 슬롯/임시 대화/채널이 새지 않음
void main() {
  late AdmissionRig rig;
  late Completer<void> gate;
  late List<CryptoSession> created;

  setUp(() {
    rig = AdmissionRig.create();
    gate = Completer<void>();
    created = <CryptoSession>[];
    rig.registry.debugCreateSession = () async {
      await gate.future;
      final session = await rig.engine.createSession();
      created.add(session);
      return session;
    };
  });

  test('they already count against the per-host and overall caps', () async {
    final held = [
      for (var i = 0; i < kMaxPendingHandshakesPerHost; i++)
        rig.connect('192.168.1.66', 5000 + i),
    ];
    expect(rig.registry.debugInboundReservations, held.length);

    final fifth = rig.connect('192.168.1.66', 6000);
    final other = rig.connect('192.168.1.67', 6000);
    await pumpEventQueue();
    expect(fifth.closed(), isTrue, reason: 'over the host cap, refused early');
    expect(other.closed(), isFalse, reason: 'another host still fits');
    expect(rig.registry.debugInboundReservations, held.length + 1);

    gate.complete();
    await Future.wait([...held.map((c) => c.accepted), other.accepted]);
    await pumpEventQueue();
    expect(
      rig.store.conversations,
      hasLength(kMaxPendingHandshakesPerHost + 1),
    );
  });

  test(
    'a slot is given back once the link is registered — never counted twice',
    () async {
      final held = [
        for (var i = 0; i < kMaxPendingHandshakesPerHost; i++)
          rig.connect('192.168.1.66', 5000 + i),
      ];
      gate.complete();
      await Future.wait(held.map((c) => c.accepted));
      await pumpEventQueue();
      expect(rig.registry.debugInboundReservations, 0);

      // 링크 넷이 미인증으로 세어지니 다섯째는 거부
      final fifth = rig.connect('192.168.1.66', 6000);
      await fifth.accepted;
      await pumpEventQueue();
      expect(fifth.closed(), isTrue);

      // 하나가 끊기면 정확히 한 자리가 남(예약이 음수로 새거나 두 번 세어지지 않음)
      await held.first.hangUp();
      await pumpEventQueue();
      final sixth = rig.connect('192.168.1.66', 6001);
      final seventh = rig.connect('192.168.1.66', 6002);
      await Future.wait([sixth.accepted, seventh.accepted]);
      await pumpEventQueue();
      expect(sixth.closed(), isFalse, reason: 'the freed slot is reusable');
      expect(seventh.closed(), isTrue, reason: 'only one slot was freed');
      expect(rig.registry.debugInboundReservations, 0);
    },
  );

  test('a peer that hangs up mid-creation leaves nothing behind', () async {
    final conn = rig.connect('192.168.1.66', 5000);
    // 세션을 만드는 중에 상대가 끊음: 아직 아무도 안 듣고 있어서 close는 링크가 붙어야 끝남
    final hungUp = conn.hangUp();
    gate.complete();
    await Future.wait([conn.accepted, hungUp]);
    await pumpEventQueue(times: 60);

    expect(rig.registry.debugInboundReservations, 0);
    expect(
      rig.store.conversations,
      isEmpty,
      reason: 'the unidentified tile goes',
    );
    expect(rig.registry.activeConversationIds, isEmpty);
    for (var i = 0; i < kMaxPendingHandshakesPerHost; i++) {
      final ok = rig.connect('192.168.1.66', 6000 + i);
      await ok.accepted;
      expect(ok.closed(), isFalse, reason: 'the dead socket holds no slot');
    }
  });

  test('disposing mid-creation leaves no slot, tile or open channel', () async {
    final conn = rig.connect('192.168.1.66', 5000);
    expect(rig.registry.debugInboundReservations, 1);
    expect(
      rig.store.conversations,
      hasLength(1),
      reason: 'the provisional tile',
    );

    final disposing = rig.registry.disposeAll(); // 세션 생성이 끝나기 전에 dispose
    gate.complete();
    await Future.wait([conn.accepted, disposing]);
    await pumpEventQueue();

    expect(created, hasLength(1), reason: 'the late session did get created');
    expect(rig.registry.debugInboundReservations, 0);
    expect(rig.store.conversations, isEmpty, reason: 'no ghost peer tile');
    expect(conn.closed(), isTrue, reason: 'the channel was closed');
    expect(rig.registry.activeConversationIds, isEmpty);
  });

  test(
    'a session that cannot be created frees the slot and cleans up',
    () async {
      rig.registry.debugCreateSession = () async => throw StateError('no keys');
      final conn = rig.connect('192.168.1.66', 5000);

      await expectLater(conn.accepted, throwsA(isA<StateError>()));
      await pumpEventQueue();
      expect(rig.registry.debugInboundReservations, 0);
      expect(rig.store.conversations, isEmpty);
      expect(conn.closed(), isTrue);

      // 이제 정상: 자리가 새지 않았음
      rig.registry.debugCreateSession = rig.engine.createSession;
      for (var i = 0; i < kMaxPendingHandshakesPerHost; i++) {
        final ok = rig.connect('192.168.1.66', 6000 + i);
        await ok.accepted;
        expect(ok.closed(), isFalse, reason: 'slot $i is free');
      }
    },
  );
}
