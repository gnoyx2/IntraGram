import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/network/protocol.dart';
import 'package:intragram/network/room_integrity.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'support/test_identities.dart';

Map<String, dynamic> message(String id, [String text = 'hello']) =>
    InnerFrame.message(id: id, text: text, ttlSeconds: 5, timestampMs: 10);

void main() {
  final alice = testIdentity('a');
  final host = testPeerId('c');
  late RoomIntegrityBook sender;
  late RoomIntegrityBook receiver;
  setUp(() {
    sender = RoomIntegrityBook()
      ..join('local-a', 'random-shared-room', [alice.peerId], host: host);
    receiver = RoomIntegrityBook()
      ..join('local-b', 'random-shared-room', [alice.peerId], host: host);
    addTearDown(sender.dispose);
    addTearDown(receiver.dispose);
  });

  test(
    'real author signature binds payload, key, counter and shared room',
    () async {
      final wire = (await sender.sign('local-a', alice, message('m1')))!;
      final event = RoomAuthorEvent.fromWire(wire, hostPeerId: host)!;
      expect(await event.verify(wire), isTrue);
      expect(await event.verify({...wire, 'text': 'forged'}), isFalse);
      expect(
        await receiver.observe('local-b', wire, actorId: alice.peerId),
        isTrue,
      );
      expect(
        receiver.observeCheckpoint(
          'local-b',
          sender.checkpoint('local-a'),
          observerId: alice.peerId,
        ),
        isTrue,
      );
      expect(receiver.status('local-b'), RoomIntegrityStatus.verified);
      final again = (await sender.sign('local-a', alice, message('m1')))!;
      expect(
        again['authorSig'],
        wire['authorSig'],
        reason: 'resend keeps counter and signature',
      );
      final second = (await sender.sign('local-a', alice, message('m2')))!;
      expect(second['authorCounter'], event.counter + 1);
      expect(second['prevAuthorHash'], event.hash);
      expect(
        await receiver.observe('local-b', second, actorId: alice.peerId),
        isTrue,
      );
    },
  );

  test(
    'same author counter with a different valid signature detects equivocation',
    () async {
      final first = (await sender.sign('local-a', alice, message('m1')))!;
      expect(
        await receiver.observe('local-b', first, actorId: alice.peerId),
        isTrue,
      );
      final divergent = await RoomAuthorEvent.sign(
        alice,
        roomId: 'random-shared-room',
        hostPeerId: host,
        counter: RoomAuthorEvent.fromWire(first, hostPeerId: host)!.counter,
        previousHash: base64.encode(Uint8List(32)),
        payload: message('m-other'),
      );
      expect(
        await receiver.observe('local-b', {
          ...message('m-other'),
          ...divergent.toWire(),
        }, actorId: alice.peerId),
        isFalse,
      );
      expect(receiver.status('local-b'), RoomIntegrityStatus.conflict);
    },
  );

  test(
    'forgery, wrong actor and replay into a different room fail closed',
    () async {
      final wire = (await sender.sign('local-a', alice, message('m1')))!;
      expect(
        await receiver.observe('local-b', {
          ...wire,
          'authorSig': base64.encode(Uint8List(64)),
        }, actorId: alice.peerId),
        isFalse,
      );
      receiver.remove('local-b');
      receiver.join('local-b', 'new-room', [alice.peerId], host: host);
      expect(
        await receiver.observe('local-b', wire, actorId: alice.peerId),
        isFalse,
      );
      receiver.remove('local-b');
      receiver.join('local-b', 'random-shared-room', [
        alice.peerId,
      ], host: host);
      expect(
        await receiver.observe('local-b', wire, actorId: testPeerId('b')),
        isFalse,
      );
    },
  );

  test('rejoining the room or a relock wipe never reuses a counter the room '
      'still holds', () async {
    Future<void> sendAndObserve(String id) async {
      final wire = (await sender.sign('local-a', alice, message(id)))!;
      expect(
        await receiver.observe('local-b', wire, actorId: alice.peerId),
        isTrue,
        reason: id,
      );
    }

    await sendAndObserve('m1');
    sender
      ..remove('local-a')
      ..join('local-a', 'random-shared-room', [alice.peerId], host: host);
    await sendAndObserve('m2');
    sender
      ..clear()
      ..join('local-a', 'random-shared-room', [alice.peerId], host: host);
    await sendAndObserve('m3');
    expect(receiver.status('local-b'), isNot(RoomIntegrityStatus.conflict));
  });

  test('conflicting checkpoint roots are retained as a conflict', () {
    final checkpoint = sender.checkpoint('local-a');
    expect(
      receiver.observeCheckpoint(
        'local-b',
        checkpoint,
        observerId: alice.peerId,
      ),
      isTrue,
    );
    expect(
      receiver.observeCheckpoint('local-b', {
        ...checkpoint,
        'merkleRoot': base64.encode(Uint8List(32)),
      }, observerId: alice.peerId),
      isFalse,
    );
    expect(receiver.status('local-b'), RoomIntegrityStatus.conflict);
  });

  test('unsigned legacy events work without a verification badge', () async {
    expect(
      await receiver.observe('local-b', message('old'), actorId: alice.peerId),
      isTrue,
    );
    expect(receiver.status('local-b'), RoomIntegrityStatus.waiting);
  });

  test(
    'removed rooms cancel queued signatures without retaining old payload',
    () async {
      final pending = sender.sign('local-a', alice, message('cancelled'));
      sender.clear();
      expect(await pending, isNull);
      expect(sender.scope('local-a'), isNull);
    },
  );

  test(
    'counter one requires a zero genesis hash and unknown scopes fail closed',
    () async {
      final event = await RoomAuthorEvent.sign(
        alice,
        roomId: 'random-shared-room',
        hostPeerId: host,
        counter: 1,
        previousHash: base64.encode(List.filled(32, 1)),
        payload: message('bad-genesis'),
      );
      expect(
        await receiver.observe('local-b', {
          ...message('bad-genesis'),
          ...event.toWire(),
        }, actorId: alice.peerId),
        isFalse,
      );
      expect(receiver.status('local-b'), RoomIntegrityStatus.conflict);
      expect(
        await receiver.observe('unjoined', {
          ...message('bad-genesis'),
          ...event.toWire(),
        }, actorId: alice.peerId),
        isFalse,
      );
      expect(receiver.scope('unjoined'), isNull);
    },
  );

  test('sliding window and lifecycle wipe bound memory', () async {
    for (var i = 0; i <= RoomIntegrityBook.window; i++) {
      final wire = (await sender.sign('local-a', alice, message('m$i')))!;
      expect(
        await receiver.observe('local-b', wire, actorId: alice.peerId),
        isTrue,
      );
    }
    expect(receiver.retainedEvents('local-b'), RoomIntegrityBook.window);
    final store = InMemoryStore();
    store.roomIntegrity.join('room', 'scope', [alice.peerId], host: host);
    store.wipeConversation('room');
    expect(store.roomIntegrity.scope('room'), isNull);
    store.roomIntegrity.join('room', 'scope', [alice.peerId], host: host);
    store.secureWipe();
    expect(store.roomIntegrity.scope('room'), isNull);
    store.dispose();
  });
}
