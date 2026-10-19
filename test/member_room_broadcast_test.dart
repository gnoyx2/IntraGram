import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/peer_link.dart';
import 'package:intragram/store/models.dart';

import 'support/member_room_rig.dart';

void main() {
  test(
    'partial host write fails visibly and retry keeps the same id',
    () async {
      final r = await MemberRoomRig.create();
      final roomId = r.rig.registry.appRoomId!;
      final failedLink = r.hostLinkOf(1);
      r.faults.hostChannels[1].failAdds = true;

      await r.rig.registry.sendText(roomId, 'room-message');
      await pumpEventQueue(times: 40);
      final message = r.rig.store
          .messages(roomId)
          .singleWhere((m) => m.text == 'room-message');
      expect(message.delivery, DeliveryState.failed);
      expect(failedLink.isClosed, isTrue);
      r.rig.store.applyReadReceipt(message.id, 'peer0');
      expect(
        r.rig.store.messageById(message.id)?.delivery,
        DeliveryState.failed,
      );
      expect(r.rig.store.messageById(message.id)?.readBy, contains('peer0'));
      expect(
        r.rig.remoteStores[1]
            .messages('remote1')
            .where((m) => m.id == message.id),
        isEmpty,
      );
      for (final i in [0, 2]) {
        expect(
          r.rig.remoteStores[i]
              .messages('remote$i')
              .where((m) => m.id == message.id),
          hasLength(1),
        );
      }

      r.rig.registry.resendFailed(message.id);
      await r.until(
        () =>
            r.rig.store.messageById(message.id)?.delivery == DeliveryState.read,
      );
      expect(r.rig.store.messageById(message.id)?.delivery, DeliveryState.read);
      expect(
        r.rig.store.messages(roomId).where((m) => m.text == 'room-message'),
        hasLength(1),
      );
      for (final i in [0, 2]) {
        expect(
          r.rig.remoteStores[i]
              .messages('remote$i')
              .where((m) => m.id == message.id),
          hasLength(1),
          reason: 'a partial retry must not duplicate a delivered message',
        );
      }
    },
  );

  test(
    'an open link seal failure fails the host message and closes it',
    () async {
      final r = await MemberRoomRig.create();
      final roomId = r.rig.registry.appRoomId!;
      final failedLink = r.hostLinkOf(2);
      await r.faults.sessions.poison(2);

      await r.rig.registry.sendText(roomId, 'seal-failure');

      expect(failedLink.isClosed, isTrue);
      expect(
        r.rig.store
            .messages(roomId)
            .singleWhere((m) => m.text == 'seal-failure')
            .delivery,
        DeliveryState.failed,
      );
    },
  );

  test('a room with no connected recipients does not mark text sent', () async {
    final r = await MemberRoomRig.create();
    final roomId = r.rig.registry.appRoomId!;
    for (final remote in r.rig.remotes) {
      await remote.close();
    }
    await r.until(() => r.rig.registry.linksForTransfer(roomId).isEmpty);

    await r.rig.registry.sendText(roomId, 'nobody-home');

    expect(
      r.rig.store
          .messages(roomId)
          .singleWhere((m) => m.text == 'nobody-home')
          .delivery,
      DeliveryState.failed,
    );
  });

  test('relay failure closes only the member that missed the frame', () async {
    final r = await MemberRoomRig.create();
    final failedLink = r.hostLinkOf(1);
    r.faults.hostChannels[1].failAdds = true;

    await r.rig.remotes[0].sendText('from-member', ttlSeconds: 0);
    await r.until(() => failedLink.isClosed);

    expect(failedLink.isClosed, isTrue);
    expect(r.hostLinkOf(2).isClosed, isFalse);
    expect(
      r.rig.remoteStores[2]
          .messages('remote2')
          .where((m) => m.text == 'from-member'),
      hasLength(1),
    );
  });

  test('a fast read receipt is not downgraded by send completion', () async {
    final r = await MemberRoomRig.create();
    final roomId = r.rig.registry.appRoomId!;
    r.faults.hostChannels[0].onAdd = (_) {
      final message = r.rig.store
          .messages(roomId)
          .singleWhere((m) => m.text == 'read-fast');
      r.rig.store.setDelivery(message.id, DeliveryState.read);
    };

    await r.rig.registry.sendText(roomId, 'read-fast');

    expect(
      r.rig.store
          .messages(roomId)
          .singleWhere((m) => m.text == 'read-fast')
          .delivery,
      DeliveryState.read,
    );
  });
}
