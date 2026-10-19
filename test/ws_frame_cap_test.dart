import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/store/in_memory_store.dart';

// 인증 전 소켓이 거대한 메시지 하나로 메모리를 채우지 못함: 서버가 다 모으기 전에 끊음
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late InMemoryStore store;
  late LinkRegistry registry;
  late LocalServer server;
  late ({String host, int port}) bound;

  setUp(() async {
    store = InMemoryStore();
    final identity = AppIdentity(
      peerId: '0' * 32,
      alias: 'srv-host-42',
      platform: 'Linux',
    );
    registry = LinkRegistry(
      store: store,
      crypto: CryptoEngine(),
      identity: identity,
    );
    server = LocalServer(
      registry: registry,
      identity: identity,
      onInboundError: (_, _) {},
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    bound = (await server.start())!;
  });

  tearDown(() async {
    await server.stop();
    await registry.disposeAll();
    store.dispose();
  });

  // 1.5 MiB는 앱 프레임 상한(2 MiB)보다 작아서 예전엔 서버가 다 모은 뒤 형식 오류로 버리고 핸드셰이크
  // 시한(12초)까지 열어 뒀음. 이제는 첫 메시지 예산(64 KiB)에서 바로 끊김
  test('a large first message is cut off before hello', () async {
    final socket = await WebSocket.connect(
      'ws://${bound.host}:${bound.port}/ws',
    );
    socket.add('x' * (1536 * 1024));
    await socket.drain<void>().timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.conversations, isEmpty);
  });
}
