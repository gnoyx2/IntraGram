import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/store/models.dart';

import 'support/handshake_pair.dart';

void main() {
  test('room member must not turn its host into a member', () async {
    final p = await connectedPair();
    addTearDown(() async {
      await p.linkA.close();
      await p.linkB.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });
    p.storeB.updateConversation(
      'cB',
      (c) => c.copyWith(isRoom: true, memberCount: 2),
    );
    expect(p.storeB.conversation('cB')!.hostAlias, isNull);
    await p.linkA.sendRawInner({'k': 'room_join', 'count': 2});
    await pumpEventQueue(times: 60);
    expect(p.storeB.conversation('cB')!.hostAlias, isNull);
  });

  test('malformed numeric field must not throw', () {
    final wire =
        jsonDecode('{"k":"file_offer","size":1e999}') as Map<String, dynamic>;
    expect(() => InboundInner.fromJson(wire), returnsNormally);
  });

  test('host relay must receive no unauthorized frame', () async {
    final p = await connectedPair();
    addTearDown(() async {
      await p.linkA.close();
      await p.linkB.close();
      p.storeA.dispose();
      p.storeB.dispose();
    });
    p.storeB.updateConversation(
      'cB',
      (c) => c.copyWith(isRoom: true, memberCount: 3),
    );
    p.storeB.upsertConversation(conv('private', 'other'));
    p.storeB.addMessage(
      EphemeralMessage(
        id: 'private-message',
        conversationId: 'private',
        direction: MessageDirection.outgoing,
        kind: MessageKind.text,
        senderAlias: 'host',
        createdAt: DateTime.now(),
        text: 'private',
        delivery: DeliveryState.sent,
      ),
    );
    final forwarded = <Map<String, dynamic>>[];
    p.linkB.onRoomFrame = forwarded.add;
    await p.linkA.sendRawInner({'k': 'burn', 'id': 'private-message'});
    await pumpEventQueue(times: 60);
    expect(p.storeB.messageById('private-message'), isNotNull);
    expect(forwarded, isEmpty);
  });
}
