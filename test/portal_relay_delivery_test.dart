import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/portal_guest.dart';

void main() {
  late InMemoryStore store;
  late LinkRegistry registry;

  setUp(() {
    store = InMemoryStore();
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
  });

  Future<List<Guest>> connectGuests(List<String> aliases) async {
    final guests = <Guest>[];
    for (final alias in aliases) {
      final guest = Guest();
      await registry.acceptInbound(
        guest.wire,
        remoteHost: '192.168.1.50',
        requiredWebToken: () => kTestPortalToken,
      );
      guest.hello(alias);
      guests.add(guest);
    }
    await pumpEventQueue(times: 40);
    return guests;
  }

  test('host text to browser guests stays a plain message frame', () async {
    final guests = await connectGuests(<String>['guest-a']);
    final states = guests[0].inboundOfKind('room_state').length;

    await registry.sendText(registry.portalRoomId!, 'hello guests');
    await pumpEventQueue(times: 40);

    final message = guests[0].inboundOfKind('msg').last;
    expect(message['text'], 'hello guests');
    expect(message.keys, isNot(contains('pid')));
    expect(message.keys, isNot(contains('authorSig')));
    expect(guests[0].inboundOfKind('room_state'), hasLength(states));
  });

  test('a reaction is relayed between guests with the sender tag', () async {
    final guests = await connectGuests(<String>['guest-a', 'guest-b']);
    guests[0].say('m1', 'poll');
    await pumpEventQueue(times: 40);

    guests[1].react('m1', '👍');
    await pumpEventQueue(times: 40);

    final relayed = guests[0].inboundOfKind('react');
    expect(relayed, isNotEmpty);
    expect(relayed.last['from'], 'guest-b');
    expect(
      store.messageById('m1')!.reactions.values.expand((s) => s),
      contains('👍'),
    );
  });

  test(
    'a screenshot notice is relayed to the room and logged on the host',
    () async {
      final guests = await connectGuests(<String>['guest-a', 'guest-b']);
      guests[0].screenshot();
      await pumpEventQueue(times: 40);

      final relayed = guests[1].inboundOfKind('screenshot');
      expect(relayed, hasLength(1));
      expect(relayed.single['from'], 'guest-a');

      final system = store
          .messages(registry.portalRoomId!)
          .where(
            (m) => m.systemEvent?.kind == SystemEventKind.screenshotByPeer,
          );
      expect(system, isNotEmpty);
      expect(
        guests[0].inboundOfKind('screenshot'),
        isEmpty,
        reason: 'the origin never gets its own notice echoed back',
      );
    },
  );

  test('a file offer without a source address is not relayed', () async {
    final guests = await connectGuests(<String>['guest-a', 'guest-b']);
    guests[0].offerFile('f1');
    await pumpEventQueue(times: 40);

    expect(
      guests[1].inboundOfKind('file_offer'),
      isEmpty,
      reason: 'no sh/sp — the recipient could not pull the bytes anyway',
    );
  });

  test(
    'a web guest cannot relay an unauthenticated file source address',
    () async {
      final guests = await connectGuests(<String>[
        'guest-a',
        'guest-b',
        'guest-c',
      ]);
      guests[0].offerFile('f9', srcHost: '192.168.1.9', srcPort: 7890);
      await pumpEventQueue(times: 40);

      for (final other in <Guest>[guests[1], guests[2]]) {
        expect(other.inboundOfKind('file_offer'), isEmpty);
      }
      expect(
        guests[0].inboundOfKind('file_offer'),
        isEmpty,
        reason: 'the origin never gets its own offer echoed back',
      );
    },
  );
}
