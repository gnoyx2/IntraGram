import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';
import 'package:intragram/store/models.dart';

import 'support/portal_guest.dart';

// 웹 게스트 → 호스트 파일 제안의 수락·거절 라우팅과 발신 주소 일치를 검증함
void main() {
  late InMemoryStore store;
  late LinkRegistry registry;
  late Directory saveDir;

  setUp(() {
    store = InMemoryStore();
    saveDir = Directory.systemTemp.createTempSync('intragram_guest_accept');
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity(),
      chooseDirectory: (_) async => saveDir.path,
    );
  });

  tearDown(() async {
    await registry.disposeAll();
    store.dispose();
    saveDir.deleteSync(recursive: true);
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

  test('host accept of a web guest push offer reaches that guest', () async {
    final guests = await connectGuests(<String>['guest-a']);
    guests.single.offerFile('f1');
    await pumpEventQueue(times: 40);
    expect(store.transfer('f1')?.state, TransferState.offered);

    await registry.acceptTransfer('f1');
    await pumpEventQueue(times: 40);

    final accepts = guests.single.inboundOfKind('file_accept');
    expect(accepts, hasLength(1));
    expect(accepts.single['id'], 'f1');
    expect(accepts.single['at'], 'attempt-f1');
    expect(accepts.single['tok'], isNotEmpty);
  });

  test('a web guest offer must name its own address as the source', () async {
    final guests = await connectGuests(<String>['guest-a']);
    guests.single.offerFile('f3', srcHost: '192.168.1.9', srcPort: 7890);
    await pumpEventQueue(times: 40);
    expect(
      store.transfer('f3'),
      isNull,
      reason: 'a foreign address is refused',
    );

    guests.single.offerFile('f4', srcHost: '192.168.1.50', srcPort: 7890);
    await pumpEventQueue(times: 40);
    expect(store.transfer('f4')?.state, TransferState.offered);
  });

  test('host reject of a web guest offer reaches only that guest', () async {
    final guests = await connectGuests(<String>['guest-a', 'guest-b']);
    guests[0].offerFile('f2');
    await pumpEventQueue(times: 40);

    await registry.rejectTransfer('f2');
    await pumpEventQueue(times: 40);

    expect(guests[0].inboundOfKind('file_reject'), hasLength(1));
    expect(guests[1].inboundOfKind('file_reject'), isEmpty);
  });
}
