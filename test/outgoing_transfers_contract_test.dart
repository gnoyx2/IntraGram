import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/network_guard.dart' show SecurityException;
import 'package:intragram/network/registry/outgoing_transfers.dart';
import 'package:intragram/store/models.dart';

import 'support/transfer_rig.dart';

// EOF와 ACK의 결합 규칙, attempt/수신자 귀속, 재시도의 mode/토큰
// 회전, 수신자별 독립성: 처리기를 직접 몰아서 EOF/ACK 순서를 결정적으로 만듦

typedef _Open = ({StreamSubscription<List<int>> sub, OutgoingDownload dl});

Future<void> _settle() => pumpEventQueue(times: 60);

void main() {
  late TransferRig rig;

  OutgoingTransfers out() => rig.registry.debugOutgoing;

  ({String key, String attemptId, String? pullToken, String phase}) rec(
    String id, [
    int i = 0,
  ]) => out()
      .debugRecipients(id)
      .firstWhere((r) => r.key == TransferRig.keyOf(i));

  // i번째 수신자로 GET을 시작하고 body를 일시정지한 채 돌려줌 (EOF 시점을 테스트가 정함)
  Future<_Open> open(String id, {int i = 0, bool paused = true}) async {
    final r = rec(id, i);
    final dl = await out().openDownload(
      transferId: id,
      attemptId: r.attemptId,
      token: r.pullToken!,
      declaredSize: rig.store.transfer(id)!.totalBytes,
    );
    final sub = dl!.body.listen((_) {}, onError: (Object _) {});
    if (paused) sub.pause();
    return (sub: sub, dl: dl);
  }

  void ack(String id, String attempt, [int i = 0]) => out().handleFileReceived(
    id,
    attemptId: attempt,
    actorKey: TransferRig.keyOf(i),
  );

  TransferState state(String id) => rig.store.transfer(id)!.state;

  group('1:1 encrypted pull', () {
    late FileTransfer t;
    setUp(() async {
      rig = await TransferRig.create(
        ackTimeout: const Duration(milliseconds: 250),
      );
      t = await rig.offerVoice();
    });

    test('an ACK that beats the EOF is held, then completes at EOF', () async {
      final o = await open(t.id);
      final attempt = rec(t.id).attemptId;
      ack(t.id, attempt);
      expect(state(t.id), TransferState.transferring);
      o.sub.resume();
      await _settle();
      expect(state(t.id), TransferState.complete);
    });

    test('an ACK before any data moved (premature) is ignored', () async {
      final attempt = rec(t.id).attemptId;
      ack(t.id, attempt); // GET 시작 전
      expect(rec(t.id).phase, 'offered');
      final o = await open(t.id, paused: false);
      await o.sub.asFuture<void>();
      await _settle();
      expect(state(t.id), TransferState.transferring, reason: 'EOF only');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(state(t.id), TransferState.failed, reason: 'no ACK → timeout');
    });

    test('an ACK from another actor is ignored', () async {
      final o = await open(t.id, paused: false);
      await o.sub.asFuture<void>();
      await _settle();
      out().handleFileReceived(
        t.id,
        attemptId: rec(t.id).attemptId,
        actorKey: 'someone-else',
      );
      expect(state(t.id), TransferState.transferring);
    });

    test(
      'retry keeps pull, rotates attempt+token; a stale ACK is inert',
      () async {
        final o1 = await open(t.id, paused: false);
        await o1.sub.asFuture<void>();
        final oldAttempt = rec(t.id).attemptId;
        final oldToken = rec(t.id).pullToken;
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(state(t.id), TransferState.failed);

        await rig.registry.retryTransfer(t.id);
        final fresh = rec(t.id);
        expect(rig.registry.outgoingSource(t.id)!.mode, FileTransferMode.pull);
        expect(fresh.attemptId, isNot(oldAttempt));
        expect(fresh.pullToken, isNot(oldToken));
        expect(fresh.phase, 'offered');
        await expectLater(
          out().openDownload(
            transferId: t.id,
            attemptId: oldAttempt,
            token: oldToken!,
            declaredSize: t.totalBytes,
          ),
          throwsA(isA<SecurityException>()),
          reason: 'the previous attempt/token are dead',
        );

        final o2 = await open(t.id, paused: false);
        await o2.sub.asFuture<void>();
        await _settle();
        ack(t.id, oldAttempt); // 낡은 attempt의 ACK: 새 시도를 완료시키면 안 됨
        expect(state(t.id), TransferState.transferring);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(
          state(t.id),
          TransferState.failed,
          reason: 'new timer still ran',
        );

        await rig.registry.retryTransfer(t.id);
        final o3 = await open(t.id, paused: false);
        await o3.sub.asFuture<void>();
        await _settle();
        ack(t.id, rec(t.id).attemptId);
        expect(state(t.id), TransferState.complete);
      },
    );

    test(
      'a cancel mid-transfer can never complete, even with a late ACK',
      () async {
        final o = await open(t.id);
        final attempt = rec(t.id).attemptId;
        rig.registry.cancelTransfer(t.id);
        expect(state(t.id), TransferState.cancelled);
        o.sub.resume();
        await _settle();
        ack(t.id, attempt);
        expect(state(t.id), TransferState.cancelled);
      },
    );
  });

  group('room with two recipients', () {
    late String roomId;
    late FileTransfer t;
    setUp(() async {
      rig = await TransferRig.create(
        ackTimeout: const Duration(milliseconds: 250),
        members: 2,
      );
      roomId = await rig.formRoom();
      t = await rig.offerRoomFile(roomId, Uint8List(1000));
    });

    test('every recipient has its own attempt and token', () {
      final a = rec(t.id, 0);
      final b = rec(t.id, 1);
      expect(a.attemptId, isNot(b.attemptId));
      expect(a.pullToken, isNot(b.pullToken));
    });

    test(
      'A completes while B is still in flight — independent states',
      () async {
        final oa = await open(t.id, i: 0, paused: false);
        await oa.sub.asFuture<void>();
        await _settle();
        ack(t.id, rec(t.id, 0).attemptId, 0);
        final ob = await open(t.id, i: 1);
        expect(rec(t.id, 0).phase, 'complete');
        expect(rec(t.id, 1).phase, 'transferring');
        expect(state(t.id), TransferState.transferring);
        expect(rig.registry.outgoingSource(t.id), isNotNull);

        ob.sub.resume();
        await _settle();
        ack(t.id, rec(t.id, 1).attemptId, 1);
        expect(state(t.id), TransferState.complete);
      },
    );

    test('an ACK carrying the other recipient attempt does nothing', () async {
      final ob = await open(t.id, i: 1, paused: false);
      await ob.sub.asFuture<void>();
      await _settle();
      ack(t.id, rec(t.id, 0).attemptId, 1); // B가 A의 attempt로 ACK
      expect(rec(t.id, 1).phase, 'awaitingAck');
    });

    test('A retries while B completed — only A is rotated', () async {
      final ob = await open(t.id, i: 1, paused: false);
      await ob.sub.asFuture<void>();
      await _settle();
      ack(t.id, rec(t.id, 1).attemptId, 1);
      final oa = await open(t.id, i: 0, paused: false);
      await oa.sub.asFuture<void>();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final b = rec(t.id, 1);
      final oldA = rec(t.id, 0);
      expect(oldA.phase, 'failed');
      expect(b.phase, 'complete');

      await rig.registry.retryTransfer(t.id);
      final newA = rec(t.id, 0);
      expect(newA.attemptId, isNot(oldA.attemptId));
      expect(newA.pullToken, isNot(oldA.pullToken));
      expect(rec(t.id, 1).attemptId, b.attemptId);
      expect(rec(t.id, 1).phase, 'complete');
      ack(t.id, oldA.attemptId, 0);
      expect(rec(t.id, 0).phase, 'offered', reason: 'stale ACK is inert');
    });

    test(
      'one member disconnecting leaves the other member untouched',
      () async {
        await rig.remotes[0].close();
        await _settle();
        expect(rec(t.id, 0).phase, 'failed');
        expect(rec(t.id, 1).phase, 'offered');
        expect(rig.registry.outgoingSource(t.id), isNotNull);
        final ob = await open(t.id, i: 1, paused: false);
        await ob.sub.asFuture<void>();
        await _settle();
        expect(rec(t.id, 1).phase, 'awaitingAck');
      },
    );
  });
}
