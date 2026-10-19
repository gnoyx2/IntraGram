import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/portal_guest.dart';

// 타이머 없는 메시지는 쓴 사람만 모두에게서 지울 수 있음. 브라우저 게스트가 개발자 도구로 남의 메시지
// id를 burn해도 호스트 기록에서 안 지워지고 다른 게스트에게 중계되지 않음
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

  Future<List<Guest>> guests(int n) async {
    final out = <Guest>[];
    for (var i = 0; i < n; i++) {
      final guest = Guest();
      await registry.acceptInbound(
        guest.wire,
        remoteHost: '192.168.1.${50 + i}',
        requiredWebToken: () => kTestPortalToken,
      );
      guest.hello('guest-$i');
      out.add(guest);
    }
    await pumpEventQueue(times: 40);
    return out;
  }

  test('a guest cannot burn the host message for everyone', () async {
    final g = await guests(2);
    final room = registry.portalRoomId!;
    await registry.sendText(room, 'host words');
    await pumpEventQueue(times: 40);
    final id = store
        .messages(room)
        .firstWhere((m) => m.text == 'host words')
        .id;

    g[0].burn(id);
    await pumpEventQueue(times: 40);

    expect(store.messageById(id), isNotNull);
    expect(g[1].inboundOfKind('burn'), isEmpty);
  });

  test('a guest cannot burn another guest message', () async {
    final g = await guests(2);
    g[1].say('m-b', 'from b');
    await pumpEventQueue(times: 40);

    g[0].burn('m-b');
    await pumpEventQueue(times: 40);

    expect(store.messageById('m-b'), isNotNull);
  });

  test('a guest can burn its own message for everyone', () async {
    final g = await guests(2);
    g[0].say('m-a', 'from a');
    await pumpEventQueue(times: 40);

    g[0].burn('m-a');
    await pumpEventQueue(times: 40);

    expect(store.messageById('m-a'), isNull);
    expect(g[1].inboundOfKind('burn').map((f) => f['id']), contains('m-a'));
  });
}
