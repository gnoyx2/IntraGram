import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/app_providers.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/server_controller.dart';
import 'package:intragram/store/in_memory_store.dart';

import 'support/portal_guest.dart' show identity;

// 로컬 서버를 끄면 이미 들어온 브라우저 게스트도 나가야 함 (포털의 '꺼져 있어서 게스트가 들어올 수 없어요' 안내와 맞춤)
class _RecordingRegistry extends LinkRegistry {
  _RecordingRegistry(InMemoryStore store)
    : super(store: store, crypto: CryptoEngine(), identity: identity());

  int guestDisconnects = 0;

  @override
  Future<void> disconnectWebGuests() async {
    guestDisconnects++;
    await super.disconnectWebGuests();
  }
}

void main() {
  test('turning the server off ends browser guest links', () async {
    final store = InMemoryStore();
    final registry = _RecordingRegistry(store);
    final container = ProviderContainer(
      overrides: [linkRegistryProvider.overrideWithValue(registry)],
    );
    addTearDown(() async {
      container.dispose();
      await registry.disposeAll();
      store.dispose();
    });

    await container.read(serverControllerProvider.notifier).stop();

    expect(registry.guestDisconnects, 1);
    expect(container.read(serverControllerProvider).portalToken, isNull);
  });
}
