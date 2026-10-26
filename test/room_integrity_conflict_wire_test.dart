import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/room_integrity.dart';
import 'support/member_room_rig.dart';

void main() {
  test(
    'members reject valid but conflicting author signatures after relay',
    () async {
      final r = await MemberRoomRig.create();
      final author = r.rig.remotes[0].identity;
      // 첫 글을 직접 서명해 보내서 그 번호를 앎 (사슬은 무작위 번호에서 시작함)
      final first = (await r.senderStore.roomIntegrity.sign(
        'remote0',
        author,
        InnerFrame.message(
          id: 'first',
          text: 'first observation',
          ttlSeconds: 0,
          timestampMs: 1,
        ),
      ))!;
      await r.rig.remotes[0].sendRawInner(first);
      await r.until(
        () => r.rig.remoteStores[1]
            .messages('remote1')
            .any((message) => message.text == 'first observation'),
      );
      final payload = InnerFrame.message(
        id: 'divergent',
        text: 'other view',
        ttlSeconds: 0,
        timestampMs: 2,
      );
      final event = await RoomAuthorEvent.sign(
        author,
        roomId: r.senderStore.roomIntegrity.scope('remote0')!,
        hostPeerId: r.hostId,
        counter: RoomAuthorEvent.fromWire(first, hostPeerId: r.hostId)!.counter,
        previousHash: base64.encode(Uint8List(32)),
        payload: payload,
      );
      expect(await event.verify(payload), isTrue);
      await r.hostLinkOf(1).sendRawInner({
        ...payload,
        ...event.toWire(),
        'pid': author.peerId,
        'from': author.alias,
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
      expect(r.rig.remoteStores[1].messageById('divergent'), isNull);
    },
  );

  test(
    'contradictory host checkpoints cross E2EE and flag the member',
    () async {
      final r = await MemberRoomRig.create();
      final roomId = r.rig.registry.appRoomId!;
      final checkpoint = r.rig.store.roomIntegrity.checkpoint(roomId);
      final root = base64.decode(checkpoint['merkleRoot'] as String);
      root[0] ^= 1;
      await r.hostLinkOf(1).sendRawInner({
        ...InnerFrame.roomState(count: 4),
        ...checkpoint,
        'merkleRoot': base64.encode(root),
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
      expect(r.rig.remotes[1].isSecure, isTrue);
    },
  );
}
