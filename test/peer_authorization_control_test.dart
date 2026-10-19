import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/peer_auth_rig.dart';
import 'support/test_identities.dart';

// 파일 제어 프레임과 room_join 인가

void main() {
  late AuthRig rig;
  setUp(() async => rig = await AuthRig.create());

  group('file control frames', () {
    final calls = <String>[];
    setUp(() {
      calls.clear();
      rig.linkB.onFileReceived = (id, at, actor) =>
          calls.add('rcv:$id:$at:$actor');
      rig.linkB.onFileAccepted = (id, at, tok, actor) =>
          calls.add('acc:$id:$at:$tok:$actor');
      rig.linkB.onFileCancelled = (id, at, actor) =>
          calls.add('cnl:$id:$at:$actor');
    });

    test(
      'an unknown id or another conversation is dropped without a trace',
      () async {
        rig.storeB
          ..upsertConversation(conv('other', 'someone'))
          ..upsertTransfer(
            authTransfer('o1', 'other', TransferDirection.outgoing),
          );
        await rig.sendFromA(<String, dynamic>{
          'k': 'file_received',
          'id': 'ghost',
          'at': 'a1',
        });
        await rig.sendFromA(<String, dynamic>{
          'k': 'file_received',
          'id': 'o1',
          'at': 'a1',
        });
        expect(calls, isEmpty);
        expect(rig.relayed, isEmpty);
      },
    );

    test('an ACK for our outgoing transfer reaches the sender only', () async {
      rig.storeB.upsertTransfer(
        authTransfer('t1', 'cB', TransferDirection.outgoing),
      );
      await rig.sendFromA(<String, dynamic>{
        'k': 'file_received',
        'id': 't1',
        'at': 'a1',
      });
      expect(calls, ['rcv:t1:a1:${testPeerId('a')}']);
      expect(
        rig.relayed,
        isEmpty,
        reason: 'meant for us — never echoed to others',
      );
    });

    test('control frames without a registered route are not relayed', () async {
      rig.storeB.upsertTransfer(
        authTransfer('t2', 'cB', TransferDirection.incoming),
      );
      await rig.sendFromA(<String, dynamic>{
        'k': 'file_accept',
        'id': 't2',
        'at': 'a1',
        'tok': 'tok-9',
      });
      expect(calls, isEmpty, reason: 'we are not the sender of t2');
      expect(rig.relayed, isEmpty);
    });

    test('stale control for an incoming attempt is never relayed', () async {
      rig.storeB.upsertTransfer(
        authTransfer('stale', 'cB', TransferDirection.incoming),
      );
      await rig.sendFromA(<String, dynamic>{
        'k': 'file_cancel',
        'id': 'stale',
        'at': 'old-attempt',
      });
      expect(calls, isEmpty);
      expect(rig.relayed, isEmpty);
    });

    test(
      'a stale attempt reaches the callback with its own attempt id',
      () async {
        rig.storeB.upsertTransfer(
          authTransfer('t3', 'cB', TransferDirection.outgoing),
        );
        await rig.sendFromA(<String, dynamic>{
          'k': 'file_cancel',
          'id': 't3',
          'at': 'old-attempt',
        });
        // PeerLink는 attempt를 판단하지 않고 그대로 넘김 (낡은 attempt
        // 거부는 registry가 함: outgoing_transfers_contract_test.dart)
        expect(calls, ['cnl:t3:old-attempt:${testPeerId('a')}']);
      },
    );
  });

  group('room_join', () {
    test('an unsolicited room_join on a plain 1:1 is refused', () async {
      await rig.sendFromA(<String, dynamic>{'k': 'room_join', 'count': 2});
      final c = rig.storeB.conversation('cB')!;
      expect(c.isRoom, isFalse);
      expect(c.hostAlias, isNull);
      expect(c.hostPeerId, isNull);
      expect(rig.relayed, isEmpty);
    });

    test('we may join a room hosted by a peer we dialled', () async {
      await rig.linkB.sendRawInner(<String, dynamic>{
        'k': 'room_join',
        'count': 2,
      });
      await pumpEventQueue(times: 60);
      final c = rig.storeA.conversation('cA')!;
      expect(c.isRoom, isTrue);
      expect(c.hostAlias, 'bob-owl-22');
      expect(c.hostPeerId, testPeerId('b'));
    });

    test('joining a room drops the 1:1 auto-accept setting', () async {
      rig.storeA.updateConversation(
        'cA',
        (c) => c.copyWith(
          autoAcceptFiles: true,
          localVerified: true,
          peerVerified: true,
        ),
      );
      await rig.linkB.sendRawInner(<String, dynamic>{
        'k': 'room_join',
        'count': 2,
      });
      await pumpEventQueue(times: 60);
      final c = rig.storeA.conversation('cA')!;
      expect(c.isRoom, isTrue);
      expect(c.autoAcceptFiles, isFalse, reason: 'room files always ask first');
    });

    test(
      'a peer we verified may invite us even though it dialled us',
      () async {
        rig.storeB.updateConversation(
          'cB',
          (c) => c.copyWith(localVerified: true, peerVerified: true),
        );
        await rig.sendFromA(<String, dynamic>{'k': 'room_join', 'count': 2});
        final c = rig.storeB.conversation('cB')!;
        expect(c.isRoom, isTrue);
        expect(c.hostPeerId, testPeerId('a'));
      },
    );

    test('only the confirmed host may update a room we belong to', () async {
      rig.storeA.updateConversation(
        'cA',
        (c) => c.copyWith(
          isRoom: true,
          hostAlias: 'real-host',
          hostPeerId: 'x' * 32,
          memberCount: 3,
        ),
      );
      await rig.linkB.sendRawInner(<String, dynamic>{
        'k': 'room_join',
        'count': 9,
      });
      await rig.linkB.sendRawInner(<String, dynamic>{
        'k': 'room_state',
        'count': 9,
      });
      await pumpEventQueue(times: 60);
      final c = rig.storeA.conversation('cA')!;
      expect(c.hostAlias, 'real-host');
      expect(c.hostPeerId, 'x' * 32);
      expect(c.memberCount, 3);
    });

    test('a room we host never accepts room control from a member', () async {
      rig.storeB.updateConversation(
        'cB',
        (c) => c.copyWith(isRoom: true, memberCount: 3),
      );
      await rig.sendFromA(<String, dynamic>{'k': 'room_join', 'count': 9});
      await rig.sendFromA(<String, dynamic>{'k': 'room_state', 'count': 9});
      final c = rig.storeB.conversation('cB')!;
      expect(c.hostAlias, isNull);
      expect(c.memberCount, 3);
      expect(rig.relayed, isEmpty);
    });
  });
}
