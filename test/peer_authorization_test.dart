import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';
import 'support/peer_auth_rig.dart';
import 'support/test_identities.dart';

// 인가 입구는 기본 거부이고, 로컬에서 거부한 프레임은 dispatch도 relay 콜백도 0회

void main() {
  late AuthRig rig;
  setUp(() async => rig = await AuthRig.create());

  group('default deny', () {
    test('an unknown kind is neither dispatched nor rig.relayed', () async {
      await rig.sendFromA(<String, dynamic>{'k': 'file_wipe', 'id': 'x'});
      await rig.sendFromA(<String, dynamic>{'id': 'x'});
      expect(rig.relayed, isEmpty);
      expect(rig.storeB.transfers, isEmpty);
    });

    test(
      'malformed offers create nothing, relay nothing, keep the link',
      () async {
        for (final bad in <Map<String, Object?>>[
          {'size': 1.5},
          {'size': '5'},
          {'size': -1},
          {'size': null},
          {'id': ''},
          {'at': null},
          {'md': null},
          {'md': 'pull'}, // 토큰/endpoint 없는 pull
        ]) {
          await rig.sendFromA(authOffer('f-bad', extra: bad));
        }
        expect(rig.storeB.transfers, isEmpty);
        expect(rig.relayed, isEmpty);
        expect(rig.linkB.isClosed, isFalse);
      },
    );

    test(
      'extra keys on a frame are dropped before dispatch and relay',
      () async {
        await rig.sendFromA(<String, dynamic>{
          'k': 'msg',
          'id': 'm1',
          'text': 'hi',
          'ttl': 0,
          'ts': 1,
          'evil': 'x',
          'sh': '8.8.8.8',
        });
        expect(rig.relayed, hasLength(1));
        expect(rig.relayed.single.containsKey('evil'), isFalse);
        expect(rig.relayed.single.containsKey('sh'), isFalse);
        expect(rig.relayed.single['pid'], testPeerId('a'));
      },
    );
  });

  group('file_offer authorization', () {
    test(
      'a valid 1:1 offer is created once and stamped with its sender',
      () async {
        await rig.sendFromA(authOffer('f1'));
        final t = rig.storeB.transfer('f1')!;
        expect(t.senderPeerId, testPeerId('a'));
        expect(t.attemptId, 'a1');
        expect(rig.relayed, hasLength(1));
        expect(rig.relayed.single['pid'], testPeerId('a'));
      },
    );

    test('an id that collides with another conversation is refused', () async {
      rig.storeB
        ..upsertConversation(conv('other', 'someone'))
        ..upsertTransfer(
          authTransfer('dup', 'other', TransferDirection.incoming),
        );
      await rig.sendFromA(authOffer('dup'));
      expect(rig.storeB.transfer('dup')!.conversationId, 'other');
      expect(rig.relayed, isEmpty);
    });

    test(
      'an id that collides with our own outgoing transfer is refused',
      () async {
        rig.storeB.upsertTransfer(
          authTransfer('mine', 'cB', TransferDirection.outgoing),
        );
        await rig.sendFromA(authOffer('mine'));
        expect(
          rig.storeB.transfer('mine')!.direction,
          TransferDirection.outgoing,
        );
        expect(rig.relayed, isEmpty);
      },
    );

    test(
      'a 1:1 offer without encryption is a downgrade and is refused',
      () async {
        await rig.sendFromA(authOffer('f2', extra: {'ec': null}));
        expect(rig.storeB.transfer('f2'), isNull);
        expect(rig.relayed, isEmpty);
      },
    );

    test('pull is only for voice in a 1:1 conversation', () async {
      final pull = <String, Object?>{
        'md': 'pull',
        'tok': 'tok-1',
        'sh': '192.168.1.9',
        'sp': 7890,
      };
      await rig.sendFromA(authOffer('f3', extra: pull));
      expect(rig.storeB.transfer('f3'), isNull);
      await rig.sendFromA(authOffer('f4', extra: {...pull, 'vc': true}));
      expect(rig.storeB.transfer('f4'), isNotNull);
    });

    test(
      'a resend is idempotent; a retry offer only from the same sender',
      () async {
        final autoAccepted = <String>[];
        rig.linkB.onAutoAcceptOffer = autoAccepted.add;
        await rig.sendFromA(authOffer('f5'));
        await rig.sendFromA(authOffer('f5')); // 같은 attempt로 재전송함
        expect(
          rig.storeB.messages('cB').where((m) => m.transferId == 'f5'),
          hasLength(1),
        );

        // 다른 크기로 같은 id를 다시 → 메타데이터 불일치라 거부, 기록 그대로
        await rig.sendFromA(authOffer('f5', extra: {'at': 'a2', 'size': 99}));
        expect(rig.storeB.transfer('f5')!.totalBytes, 4);
        expect(rig.storeB.transfer('f5')!.attemptId, 'a1');

        // 실패한 전송을 같은 발신자가 새 attempt로 재offer → 새 시도로 되돌아가고
        // 사용자가 이미 수락했던 전송이라 자동 수락함
        rig.storeB.updateTransfer(
          'f5',
          (t) => t.copyWith(state: TransferState.failed, error: 'network'),
        );
        await rig.sendFromA(authOffer('f5', extra: {'at': 'a2'}));
        final t = rig.storeB.transfer('f5')!;
        expect(t.attemptId, 'a2');
        expect(t.state, TransferState.offered);
        expect(t.error, isNull);
        expect(autoAccepted, ['f5']);
      },
    );

    // 수락을 고르는 카드에 상대가 정한 이름이 그대로 뜨면 RLO로 확장자를 위장할 수 있음:
    // 저장될 이름 그대로 받아 두고, 같은 파일의 재offer도 그 이름끼리 비교함
    test('an offered name is kept the way it will be saved', () async {
      final rlo = String.fromCharCode(0x202e);
      final autoAccepted = <String>[];
      rig.linkB.onAutoAcceptOffer = autoAccepted.add;
      final disguised = {'name': 'invoice${rlo}txt.exe'};
      await rig.sendFromA(authOffer('f7', extra: disguised));
      expect(rig.storeB.transfer('f7')!.fileName, 'invoicetxt.exe');

      rig.storeB.updateTransfer(
        'f7',
        (t) => t.copyWith(state: TransferState.failed, error: 'network'),
      );
      await rig.sendFromA(authOffer('f7', extra: {...disguised, 'at': 'a2'}));
      expect(rig.storeB.transfer('f7')!.attemptId, 'a2');
      expect(autoAccepted, ['f7']);
    });

    test('a transfer in flight cannot be swapped by a new attempt', () async {
      await rig.sendFromA(authOffer('f6'));
      rig.storeB.updateTransfer(
        'f6',
        (t) => t.copyWith(state: TransferState.transferring),
      );
      await rig.sendFromA(authOffer('f6', extra: {'at': 'a2'}));
      expect(rig.storeB.transfer('f6')!.attemptId, 'a1');
    });
  });
}
