import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/store/models.dart';

import 'support/incoming_cleanup_rig.dart';

// 활성 수신/취소 뒤에도 앱이 소유한 .part가 clear/discard에서 끝까지 정리되는지:
// 정지한 body 수신 뒤 clear, 정지한 취소, gate 대기, 쓰기 도중,
// 취소 직후, 늦은 폴더 선택 (직접 pull/링크 종료/삭제 실패는 active_cleanup_link_test.dart)
void main() {
  final rig = IncomingCleanupRig();
  setUp(rig.setUp);
  tearDown(rig.tearDown);

  test('active receive is drained and its part removed by clear', () async {
    rig.store.upsertTransfer(rig.offer('t'));
    final body = StreamController<List<int>>();
    await rig.incoming.accept('t');
    final receiving = rig.startReceive('t', body.stream);
    await settle();
    expect(rig.store.transfer('t')!.state, TransferState.transferring);
    expect(rig.parts(), hasLength(1));

    await rig.incoming.clear();

    expect(rig.parts(), isEmpty, reason: 'clear must delete owned partials');
    expect(await receiving, isFalse, reason: 'the receive was drained');
    unawaited(body.close());
  });

  test(
    'clear waits for the stalled stream cancel before it completes',
    () async {
      rig.store.upsertTransfer(rig.offer('t'));
      final cancelStarted = Completer<void>();
      final finishCancel = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelStarted.complete();
          return finishCancel.future;
        },
      );
      await rig.incoming.accept('t');
      final receiving = rig.startReceive('t', body.stream);
      await settle();

      final watch = Stopwatch()..start();
      var cleared = false;
      final clearing = rig.incoming.clear().then((_) => cleared = true);
      await cancelStarted.future.timeout(const Duration(seconds: 5));
      expect(cleared, isFalse, reason: 'cancel is still finishing');
      finishCancel.complete();
      await clearing;
      expect(await receiving, isFalse);
      expect(rig.parts(), isEmpty);
      // 정지한 소스 앞에서도 취소가 stall timeout(25s)을 안 기다리고 곧바로 소스 구독까지 전달돼야 함
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test(
    'a receive waiting for a gate slot is cancelled and its part removed',
    () async {
      rig.build(maxConcurrent: 1);
      await rig.gate.acquire(); // 유일한 슬롯을 다른 전송이 쥐고 있는 상태
      rig.store.upsertTransfer(rig.offer('t'));
      await rig.incoming.accept('t');
      final receiving = rig.startReceive('t', const Stream<List<int>>.empty());
      await settle();
      expect(rig.parts(), hasLength(1));

      final watch = Stopwatch()..start();
      await rig.incoming.clear();

      expect(await receiving, isFalse);
      expect(rig.parts(), isEmpty);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test('cancel right after accept leaves no part once drained', () async {
    rig.store.upsertTransfer(rig.offer('t'));
    await rig.incoming.accept('t');
    expect(rig.parts(), hasLength(1));

    rig.incoming.cancelTransfer('t');
    await rig.incoming.discard('t');

    expect(rig.parts(), isEmpty);
    expect(rig.store.transfer('t')!.state, TransferState.cancelled);
  });

  test('two taps while choosing a folder reserve only one partial', () async {
    rig.store.upsertTransfer(rig.offer('t'));
    rig.chooser = Completer<String?>();
    final first = rig.incoming.accept('t');
    final second = rig.incoming.accept('t');
    rig.chooser!.complete(rig.dir.path);
    await Future.wait([first, second]);

    expect(rig.parts(), hasLength(1));
    await rig.incoming.clear();
    expect(rig.parts(), isEmpty);
  });

  test(
    'clear at every await depth of an in-progress write leaves no part',
    () async {
      // 쓰기 도중/청크 대기/검증 직전 등 수신 루프가 서 있을 수 있는 어느 await
      // 지점에서 clear가 들어와도 같은 불변식이 서야 함 (깊이를 0~7로 바꿔가며
      // 반복)
      for (var depth = 0; depth < 8; depth++) {
        final id = 'w$depth';
        rig.store.upsertTransfer(rig.offer(id));
        final body = StreamController<List<int>>();
        await rig.incoming.accept(id);
        final receiving = rig.startReceive(id, body.stream);
        body.add(const [1, 2, 3, 4]); // 8바이트 중 4바이트: 아직 미완성
        await pumpEventQueue(times: depth);

        await rig.incoming.clear();

        expect(rig.parts(), isEmpty, reason: 'depth $depth left a part');
        expect(await receiving, isFalse, reason: 'depth $depth not drained');
        // 아무도 listen하지 않은 컨트롤러의 close()는 영영 안 끝나서 기다리지 않음
        unawaited(body.close());
        rig.build(); // clear가 닫은 registry를 다음 회차용으로 새로 만듦
      }
    },
  );

  test('clear right after accept, at any depth, leaves no part', () async {
    for (var depth = 0; depth < 6; depth++) {
      final id = 'a$depth';
      rig.store.upsertTransfer(rig.offer(id));
      final accepting = rig.incoming.accept(id);
      await pumpEventQueue(times: depth);

      await rig.incoming.clear();
      await accepting;

      expect(rig.parts(), isEmpty, reason: 'depth $depth left a part');
      rig.build();
    }
  });

  test(
    'an accept whose folder chooser returns after clear creates nothing',
    () async {
      rig.store.upsertTransfer(rig.offer('t'));
      rig.chooser = Completer<String?>();
      final accepting = rig.incoming.accept('t');
      await pumpEventQueue(times: 10);

      await rig.incoming.clear();
      rig.chooser!.complete(rig.dir.path); // 정리가 끝난 뒤 늦게 도착한 선택
      await accepting;

      expect(rig.parts(), isEmpty, reason: 'no part for a cleared session');
      expect(rig.incoming.debugPushTokenFor('t'), isNull);
    },
  );

  test(
    'an accept whose transfer vanished while choosing creates nothing',
    () async {
      rig.store.upsertTransfer(rig.offer('t'));
      rig.chooser = Completer<String?>();
      final accepting = rig.incoming.accept('t');
      await pumpEventQueue(times: 10);

      rig.store.secureWipe(); // 소각으로 전송 레코드가 사라짐
      rig.chooser!.complete(rig.dir.path);
      await accepting;
      await rig.store.drainDisposals();

      expect(rig.parts(), isEmpty);
    },
  );
}
