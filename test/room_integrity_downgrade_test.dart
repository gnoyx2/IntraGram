import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/room_integrity.dart';
import 'support/member_room_rig.dart';
import 'support/test_identities.dart';

Map<String, dynamic> _message(String id) =>
    InnerFrame.message(id: id, text: 'hello', ttlSeconds: 0, timestampMs: 1);

// 작성자 서명은 선택 필드라서: 중계 호스트가 서명을 떼거나, 같은 범위 값을 쓰는 다른 호스트 방으로 옮겨 재생하거나,
// 내 글만으로 '검증 정상'이 뜨는 길을 막는 규칙들
void main() {
  final alice = testIdentity('a');
  final host = testPeerId('c');

  test(
    'after an author signed in this room, an unsigned message under that '
    'name is a conflict; authors that never signed still get through',
    () async {
      final sender = RoomIntegrityBook()
        ..join('a', 'scope', [alice.peerId], host: host);
      final receiver = RoomIntegrityBook()
        ..join('b', 'scope', [alice.peerId, testPeerId('d')], host: host);
      addTearDown(sender.dispose);
      addTearDown(receiver.dispose);

      expect(
        await receiver.observe('b', _message('old'), actorId: testPeerId('d')),
        isTrue,
      );
      final signed = (await sender.sign('a', alice, _message('m1')))!;
      expect(
        await receiver.observe('b', signed, actorId: alice.peerId),
        isTrue,
      );
      expect(
        await receiver.observe(
          'b',
          _message('stripped'),
          actorId: alice.peerId,
        ),
        isFalse,
      );
      expect(receiver.status('b'), RoomIntegrityStatus.conflict);
    },
  );

  test(
    'my own signed messages and a checkpoint never read as verified',
    () async {
      final book = RoomIntegrityBook()..ensureRoom('room', host: alice.peerId);
      addTearDown(book.dispose);
      book.setMembers('room', [alice.peerId]);
      await book.sign('room', alice, _message('mine'));
      book.checkpoint('room');
      expect(book.observedEvents('room'), 1);
      expect(book.status('room'), RoomIntegrityStatus.waiting);
    },
  );

  test('a signature made in one host room fails in another host room that '
      'reuses the same scope', () async {
    final sender = RoomIntegrityBook()
      ..join('a', 'scope', [alice.peerId], host: host);
    final other = RoomIntegrityBook()
      ..join('b', 'scope', [alice.peerId], host: testPeerId('e'));
    addTearDown(sender.dispose);
    addTearDown(other.dispose);
    final signed = (await sender.sign('a', alice, _message('m1')))!;
    expect(await other.observe('b', signed, actorId: alice.peerId), isFalse);
    expect(other.status('b'), RoomIntegrityStatus.conflict);
  });

  test('a host that strips a member signature on relay is caught', () async {
    final r = await MemberRoomRig.create();
    await r.rig.remotes[0].sendText('signed first', ttlSeconds: 0);
    await r.until(
      () => r.rig.remoteStores[1]
          .messages('remote1')
          .any((m) => m.text == 'signed first'),
    );
    await r.hostLinkOf(1).sendRawInner({
      ...InnerFrame.message(
        id: 'stripped',
        text: 'forged by the host',
        ttlSeconds: 0,
        timestampMs: 3,
      ),
      'pid': MemberRoomRig.memberId(0),
      'from': 'member',
    });
    await r.until(
      () =>
          r.rig.remoteStores[1].roomIntegrity.status('remote1') ==
          RoomIntegrityStatus.conflict,
    );
    expect(
      r.rig.remoteStores[1].roomIntegrity.status('remote1'),
      RoomIntegrityStatus.conflict,
    );
    expect(r.rig.remoteStores[1].messageById('stripped'), isNull);
  });

  for (final keepScope in [false, true]) {
    test('established room rejects checkpoint removal '
        '(scope retained: $keepScope)', () async {
      final r = await MemberRoomRig.create();
      final store = r.rig.remoteStores[1];
      final before = store.conversation('remote1')!;
      final scope = store.roomIntegrity.scope('remote1');
      expect(scope, isNotNull);
      await r.hostLinkOf(1).sendRawInner({
        ...InnerFrame.roomState(count: 2, peers: [r.hostId]),
        if (keepScope) 'roomIntegrityId': scope,
      });
      await r.until(
        () =>
            store.roomIntegrity.status('remote1') ==
            RoomIntegrityStatus.conflict,
      );
      expect(
        store.roomIntegrity.status('remote1'),
        RoomIntegrityStatus.conflict,
      );
      expect(store.conversation('remote1')!.memberCount, before.memberCount);
      expect(
        store.conversation('remote1')!.roomRecipientIds,
        before.roomRecipientIds,
      );
      expect(r.rig.remotes[1].isSecure, isTrue);
    });
  }
}
