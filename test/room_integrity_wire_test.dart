import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/room_integrity.dart';
import 'support/member_room_rig.dart';

void main() {
  test(
    'member signatures survive real host relay; invalid signatures never relay',
    () async {
      final r = await MemberRoomRig.create();
      final roomId = r.rig.registry.appRoomId!;
      await r.rig.remotes[0].sendText('signed member text', ttlSeconds: 0);
      await r.until(
        () => r.rig.remoteStores[1]
            .messages('remote1')
            .any((m) => m.text == 'signed member text'),
      );
      final message = r.rig.remoteStores[1]
          .messages('remote1')
          .singleWhere((m) => m.text == 'signed member text');
      expect(message.senderPeerId, MemberRoomRig.memberId(0));
      expect(
        r.rig.store.roomIntegrity.status(roomId),
        RoomIntegrityStatus.verified,
      );
      expect(
        r.rig.remoteStores[1].roomIntegrity.status('remote1'),
        RoomIntegrityStatus.verified,
      );
      final sender = r.rig.remoteStores[0].roomIntegrity;
      final valid = await sender.sign(
        'remote0',
        r.rig.remotes[0].identity,
        InnerFrame.message(
          id: 'forged',
          text: 'must not relay',
          ttlSeconds: 0,
          timestampMs: 1,
        ),
      );
      await r.rig.remotes[0].sendRawInner({
        ...valid!,
        'authorSig': base64.encode(Uint8List(64)),
      });
      await pumpEventQueue(times: 100);
      expect(r.rig.store.messageById('forged'), isNull);
      expect(r.rig.remoteStores[1].messageById('forged'), isNull);
      expect(
        r.rig.store.roomIntegrity.status(roomId),
        RoomIntegrityStatus.conflict,
      );
    },
  );

  test(
    'wipe during queued signing never transmits old host or member text',
    () async {
      final r = await MemberRoomRig.create();
      final memberSend = r.rig.remotes[0].sendText(
        'cancelled member',
        ttlSeconds: 0,
      );
      r.rig.remoteStores[0].secureWipe();
      await memberSend;
      final roomId = r.rig.registry.appRoomId!;
      final hostSend = r.rig.registry.sendText(roomId, 'cancelled host');
      r.rig.store.secureWipe();
      await hostSend;
      await pumpEventQueue(times: 100);
      expect(
        r.rig.remoteStores[1]
            .messages('remote1')
            .where(
              (m) => m.text == 'cancelled member' || m.text == 'cancelled host',
            ),
        isEmpty,
      );
      expect(r.rig.store.roomIntegrity.scope(roomId), isNull);
      expect(r.rig.remoteStores[0].roomIntegrity.scope('remote0'), isNull);
    },
  );

  test(
    'host-authored messages are signed; legacy messages still arrive',
    () async {
      final r = await MemberRoomRig.create();
      final roomId = r.rig.registry.appRoomId!;
      await r.rig.registry.sendText(roomId, 'host signed');
      await r.until(
        () => r.rig.remoteStores[0]
            .messages('remote0')
            .any((m) => m.text == 'host signed'),
      );
      expect(r.rig.remoteStores[0].roomIntegrity.observedEvents('remote0'), 1);
      await r.rig.remotes[1].sendRawInner(
        InnerFrame.message(
          id: 'legacy',
          text: 'old app',
          ttlSeconds: 0,
          timestampMs: 2,
        ),
      );
      await r.until(() => r.rig.remoteStores[0].messageById('legacy') != null);
      expect(r.rig.remoteStores[0].messageById('legacy')?.text, 'old app');
    },
  );
}
