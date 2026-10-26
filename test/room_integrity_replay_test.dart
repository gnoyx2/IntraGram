import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/audit/merkle.dart';
import 'package:intragram/network/peer_link.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/room_integrity.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';
import 'support/handshake_pair.dart' show conv;
import 'support/member_room_rig.dart';
import 'support/test_identities.dart';

Map<String, dynamic> _message(String id) =>
    InnerFrame.message(id: id, text: 'yes', ttlSeconds: 5, timestampMs: 10);

void main() {
  test('burn cancels queued and in-flight author envelopes before they can '
      'repopulate the retry cache', () async {
    final author = testIdentity('a');
    final store = InMemoryStore()..upsertConversation(conv('r', 'room'));
    addTearDown(store.dispose);
    store.roomIntegrity.join('r', 'scope', [
      author.peerId,
    ], host: author.peerId);
    for (final inFlight in [false, true]) {
      final id = 'burn-during-sign-$inFlight';
      store.addMessage(
        EphemeralMessage(
          id: id,
          conversationId: 'r',
          direction: MessageDirection.outgoing,
          kind: MessageKind.text,
          senderAlias: author.alias,
          createdAt: DateTime(2026),
          text: 'yes',
          ttlSeconds: 5,
          delivery: DeliveryState.sending,
        ),
      );
      final signing = store.roomIntegrity.sign('r', author, _message(id));
      if (inFlight) await Future<void>.value();
      store.burnMessage(id);
      expect(await signing, isNull);
      expect(store.roomIntegrity.retainedEnvelopes('r'), 0);
      expect(store.messageById(id), isNull);
    }
  });

  test('a host replaying an original valid signature in a fresh encrypted '
      'frame cannot resurrect a burned group message', () async {
    final r = await MemberRoomRig.create();
    final author = r.rig.remotes[0].identity;
    await r.rig.remotes[0].sendText('yes', ttlSeconds: 5);
    final original = r.senderStore
        .messages('remote0')
        .singleWhere((m) => m.text == 'yes');
    final wire = (await r.senderStore.roomIntegrity.sign(
      'remote0',
      author,
      InnerFrame.message(
        id: original.id,
        text: original.text!,
        ttlSeconds: original.ttlSeconds,
        timestampMs: original.createdAt.millisecondsSinceEpoch,
      ),
    ))!;
    final victim = r.rig.remoteStores[1];
    await r.until(() => victim.messageById(original.id) != null);
    expect(victim.messageById(original.id), isNotNull);
    expect(r.senderStore.roomIntegrity.retainedEnvelopes('remote0'), 1);
    r.senderStore.burnMessage(original.id);
    await r.rig.remotes[0].sendBurn(original.id);
    await r.until(() => victim.messageById(original.id) == null);
    expect(victim.messageById(original.id), isNull);
    expect(r.senderStore.roomIntegrity.retainedEnvelopes('remote0'), 0);
    final observed = victim.roomIntegrity.observedEvents('remote1');
    final unread = victim.conversation('remote1')!.unread;
    for (var i = 0; i < 3; i++) {
      expect(
        await r.hostLinkOf(1).sendRawInner({
          ...wire,
          'pid': author.peerId,
          'from': author.alias,
        }),
        isTrue,
      );
    }
    await pumpEventQueue(times: 100);
    expect(victim.messageById(original.id), isNull);
    expect(victim.roomIntegrity.observedEvents('remote1'), observed);
    expect(victim.conversation('remote1')!.unread, unread);
    expect(r.rig.remotes[1].isSecure, isTrue);
  });

  test('replay tombstones survive detailed event eviction, and receiver '
      'retains no payload envelope', () async {
    final author = testIdentity('a');
    final host = testPeerId('c');
    final sender = RoomIntegrityBook()
      ..join('s', 'scope', [author.peerId], host: host);
    final receiver = RoomIntegrityBook()
      ..join('r', 'scope', [author.peerId], host: host);
    addTearDown(sender.dispose);
    addTearDown(receiver.dispose);
    final first = (await sender.sign('s', author, _message('first')))!;
    expect(await receiver.observe('r', first, actorId: author.peerId), isTrue);
    for (var i = 0; i < RoomIntegrityBook.window; i++) {
      final wire = (await sender.sign('s', author, _message('later$i')))!;
      expect(await receiver.observe('r', wire, actorId: author.peerId), isTrue);
    }
    expect(receiver.retainedEvents('r'), RoomIntegrityBook.window);
    expect(receiver.retainedEnvelopes('r'), 0);
    final observed = receiver.observedEvents('r');
    expect(await receiver.observe('r', first, actorId: author.peerId), isFalse);
    expect(receiver.observedEvents('r'), observed);
    expect(receiver.status('r'), isNot(RoomIntegrityStatus.conflict));
  });

  test('payload commitments are salted; retirement preserves opaque '
      'checkpoints and a split-view conflict stays sticky', () async {
    final author = testIdentity('a');
    final host = testPeerId('c');
    final book = RoomIntegrityBook()
      ..join('r', 'scope', [author.peerId], host: host);
    addTearDown(book.dispose);
    final payload = _message('m');
    final first = (await book.sign('r', author, payload))!;
    final other = await RoomAuthorEvent.sign(
      author,
      roomId: 'scope',
      hostPeerId: host,
      counter: first['authorCounter'] as int,
      previousHash: first['prevAuthorHash'] as String,
      payload: payload,
    );
    final unsalted = base64.encode(
      sha256Bytes(
        utf8.encode(
          jsonEncode(['intragram/room-payload/v1', 'm', 'yes', 5, 10, '']),
        ),
      ),
    );
    expect(first['payloadCommitment'], isNot(unsalted));
    expect(first['payloadCommitment'], isNot(other.payloadCommitment));
    expect(base64.decode(first['payloadSalt'] as String), hasLength(32));
    final before = book.checkpoint('r');
    book.retireMessage('r', 'm');
    expect(book.retainedEnvelopes('r'), 0);
    expect(book.retainedEvents('r'), 1);
    expect(book.checkpoint('r'), before);
    expect(book.observeCheckpoint('r', before, observerId: host), isTrue);
    final root = base64.decode(before['merkleRoot'] as String)..[0] ^= 1;
    expect(
      book.observeCheckpoint('r', {
        ...before,
        'merkleRoot': base64.encode(root),
      }, observerId: host),
      isFalse,
    );
    for (var i = 0; i <= RoomIntegrityBook.window; i++) {
      book.observeCheckpoint('r', {
        ...before,
        'checkpointNo': i + 2,
        'merkleRoot': base64.encode(Uint8List(32)),
      }, observerId: host);
    }
    expect(book.status('r'), RoomIntegrityStatus.conflict);
  });

  test('disjoint counter saturation rejects new ranges without forgetting '
      'old signed events', () async {
    final author = testIdentity('a');
    final host = testPeerId('c');
    final receiver = RoomIntegrityBook()
      ..join('r', 'scope', [author.peerId], host: host);
    addTearDown(receiver.dispose);
    Map<String, dynamic>? first;
    for (var i = 0; i <= RoomIntegrityBook.window; i++) {
      final payload = _message('m$i');
      final event = await RoomAuthorEvent.sign(
        author,
        roomId: 'scope',
        hostPeerId: host,
        counter: 10 + i * 3,
        previousHash: base64.encode(Uint8List(32)),
        payload: payload,
      );
      final wire = {...payload, ...event.toWire()};
      first ??= wire;
      expect(
        await receiver.observe('r', wire, actorId: author.peerId),
        i < RoomIntegrityBook.window,
      );
    }
    expect(
      await receiver.observe('r', first!, actorId: author.peerId),
      isFalse,
    );
    expect(receiver.observedEvents('r'), RoomIntegrityBook.window);
  });

  test('out-of-order counters fill gaps and merge replay ranges', () async {
    final author = testIdentity('a');
    final host = testPeerId('c');
    final book = RoomIntegrityBook()
      ..join('r', 'scope', [author.peerId], host: host);
    addTearDown(book.dispose);
    var previous = base64.encode(Uint8List(32));
    final wires = <Map<String, dynamic>>[];
    for (var i = 1; i <= 3; i++) {
      final payload = _message('out-of-order-$i');
      final event = await RoomAuthorEvent.sign(
        author,
        roomId: 'scope',
        hostPeerId: host,
        counter: i,
        previousHash: previous,
        payload: payload,
      );
      wires.add({...payload, ...event.toWire()});
      previous = event.hash;
    }
    for (final index in [0, 2, 1]) {
      expect(
        await book.observe('r', wires[index], actorId: author.peerId),
        isTrue,
      );
    }
    for (final wire in wires) {
      expect(await book.observe('r', wire, actorId: author.peerId), isFalse);
    }
    expect(book.observedEvents('r'), 3);
  });
}
