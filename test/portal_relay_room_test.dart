import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
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

  test(
    'portal OFF revokes a token on an already accepted pending link',
    () async {
      String? token = kTestPortalToken;
      final guest = Guest();
      await registry.acceptInbound(
        guest.wire,
        remoteHost: '192.168.1.50',
        requiredWebToken: () => token,
      );
      token = null; // 소켓 accept 뒤 web_hello 전에 OFF됨
      guest.hello('late-guest');
      await pumpEventQueue(times: 40);

      expect(registry.portalRoomId, isNull);
      expect(store.conversations, isEmpty);
    },
  );

  test('every browser guest lands in one shared room', () async {
    await connectGuests(<String>['guest-a', 'guest-b', 'guest-c']);

    final rooms = store.conversations.where((c) => c.isRoom).toList();
    expect(rooms, hasLength(1));
    expect(registry.portalRoomId, rooms.single.id);
    expect(rooms.single.online, isTrue);
    expect(
      rooms.single.transport,
      PeerTransport.web,
      reason: 'the room UI must know its guests are plaintext',
    );
    expect(
      store.conversations.where((c) => !c.isRoom),
      isEmpty,
      reason: 'the throwaway per-socket conversations are wiped on web_hello',
    );
  });

  test(
    'a guest message is stored once and relayed to the other guests',
    () async {
      final guests = await connectGuests(<String>[
        'guest-a',
        'guest-b',
        'guest-c',
      ]);
      guests[0].say('m1', 'hey all');
      await pumpEventQueue(times: 40);

      final hostView = store.messages(registry.portalRoomId!);
      final mine = hostView.where((m) => m.text == 'hey all').toList();
      expect(mine, hasLength(1));
      expect(mine.single.senderAlias, 'guest-a');

      for (final other in <Guest>[guests[1], guests[2]]) {
        final msgs = other.inboundOfKind('msg');
        expect(msgs, isNotEmpty);
        expect(msgs.last['text'], 'hey all');
        expect(msgs.last['from'], 'guest-a');
      }

      expect(
        guests[0].inboundOfKind('msg').where((f) => f['text'] == 'hey all'),
        isEmpty,
        reason: 'the sender never gets its own message echoed back',
      );
    },
  );

  test('a host message reaches every guest', () async {
    final guests = await connectGuests(<String>['guest-a', 'guest-b']);
    await registry.sendText(registry.portalRoomId!, 'from the host');
    await pumpEventQueue(times: 40);

    for (final guest in guests) {
      final msgs = guest.inboundOfKind('msg');
      expect(msgs.last['text'], 'from the host');
      expect(msgs.last['from'], 'portal-host-7');
    }
    final hostMsg = store
        .messages(registry.portalRoomId!)
        .firstWhere((m) => m.text == 'from the host');
    expect(hostMsg.isMine, isTrue);
  });

  test('a guest that gets in hears the head count right away', () async {
    final guests = await connectGuests(<String>['guest-a', 'guest-b']);
    // 브라우저는 이 첫 프레임을 입장 승인으로 봄 (joined 없이 인원만)
    final first = guests[1].inboundOfKind('room_state').first;
    expect(first['count'], 3, reason: 'host + guest-a + guest-b');
    expect(first['joined'], isNull);
  });

  test('a guest with a wrong token hears nothing before the close', () async {
    final guest = Guest();
    await registry.acceptInbound(
      guest.wire,
      remoteHost: '192.168.1.51',
      requiredWebToken: () => 'another-token',
    );
    guest.hello('guest-x');
    await pumpEventQueue(times: 40);
    expect(guest.inboundOfKind('room_state'), isEmpty);
  });

  test('a full room turns the next guest away and leaves no tile', () async {
    final guests = <Guest>[];
    for (var i = 0; i <= kMaxWebGuests; i++) {
      final guest = Guest();
      // host별 접속 빈도 상한에 안 걸리게 주소를 나눔
      await registry.acceptInbound(
        guest.wire,
        remoteHost: '192.168.1.${10 + i}',
        requiredWebToken: () => kTestPortalToken,
      );
      guest.hello('guest-$i');
      await pumpEventQueue(times: 20);
      guests.add(guest);
    }

    final turnedAway = guests.last;
    expect(turnedAway.inboundOfKind('room_full'), hasLength(1));
    expect(turnedAway.inboundOfKind('room_state'), isEmpty);
    expect(turnedAway.closed, isTrue);
    expect(
      store.conversation(registry.portalRoomId!)!.memberCount,
      kMaxWebGuests + 1,
      reason: 'the host and the guests who got in',
    );
    expect(store.conversations.where((c) => !c.isRoom), isEmpty);
  });

  test('members get a room_state frame on every join and leave', () async {
    final guests = await connectGuests(<String>[
      'guest-a',
      'guest-b',
      'guest-c',
    ]);

    final joinsSeenByA = guests[0]
        .inboundOfKind('room_state')
        .where((f) => f['joined'] != null)
        .map((f) => f['joined'])
        .toList();
    expect(joinsSeenByA, containsAll(<String>['guest-b', 'guest-c']));

    await guests[2].disconnect();
    await pumpEventQueue(times: 40);

    final leaves = guests[0]
        .inboundOfKind('room_state')
        .where((f) => f['left'] == 'guest-c')
        .toList();
    expect(leaves, isNotEmpty);
    expect(leaves.last['count'], 3, reason: 'host + guest-a + guest-b');
  });

  test(
    'the portal room goes offline only when the last guest leaves',
    () async {
      final guests = await connectGuests(<String>['guest-a', 'guest-b']);
      final portalId = registry.portalRoomId!;

      await guests[0].disconnect();
      await pumpEventQueue(times: 40);
      expect(store.conversation(portalId)!.online, isTrue);

      await guests[1].disconnect();
      await pumpEventQueue(times: 40);
      expect(store.conversation(portalId)!.online, isFalse);
    },
  );
}
