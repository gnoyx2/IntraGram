import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/store/in_memory_store.dart';

void main() {
  // 바인딩이 서빙용 웹 클라이언트의 rootBundle은 주지만 모든 실제
  // 요청에 400으로 답하는 HttpOverrides mock도 설치하므로,
  // 그 mock을 걷어내야 테스트가 내장 서버와 실제로 통신함
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late InMemoryStore store;
  late LinkRegistry registry;
  late LocalServer server;
  late ({String host, int port}) bound;
  late HttpClient client;
  final inboundErrors = <Object>[];

  setUpAll(() async {
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
      onInboundError: (error, _) => inboundErrors.add(error),
      preferredPort: 0, // OS가 배정한 ephemeral 포트
      // 이 테스트는 프로세스 안에서 실제 HTTP로 자기 자신하고만 통신하니 실제 LAN 인터페이스가 필요 없어 loopback을 고정
      // (NetworkGuard.localBindAddress는 프로덕션에서 loopback을
      // 일부러 제외해 서버가 닿을 수 없는 주소에 조용히 바인딩되지 않게 함)
      bindAddress: InternetAddress.loopbackIPv4,
    );
    final b = await server.start();
    expect(b, isNotNull, reason: 'server must bind to a link-local address');
    bound = b!;
    client = HttpClient();
  });

  tearDownAll(() async {
    client.close(force: true);
    await server.stop();
    await registry.disposeAll();
    store.dispose();
  });

  Uri url(String path) => Uri.parse('http://${bound.host}:${bound.port}$path');

  test('binds only to a link-local address', () {
    expect(server.isRunning, isTrue);
    final first = int.parse(server.boundHost!.split('.').first);
    expect(
      first == 10 ||
          first == 172 ||
          first == 192 ||
          first == 127 ||
          first == 169,
      isTrue,
      reason: 'bound host ${server.boundHost} must be private / loopback',
    );
  });

  test('GET /health returns the identity JSON', () async {
    final resp = await (await client.getUrl(url('/health'))).close();
    expect(resp.statusCode, 200);
    final body = jsonDecode(await resp.transform(utf8.decoder).join());
    expect(body['app'], 'IntraGram');
    expect(body['alias'], 'srv-host-42');
  });

  test('responses carry Cache-Control: no-store', () async {
    final resp = await (await client.getUrl(url('/health'))).close();
    await resp.drain<void>();
    expect(resp.headers.value('cache-control'), 'no-store');
  });

  test('GET / serves the single-file web client', () async {
    final resp = await (await client.getUrl(url('/'))).close();
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'text/html');
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('IntraGram'));
    expect(body, contains('/ws'));
  });

  test('POST /api/transfer without a transfer id is a 400', () async {
    final req = await client.postUrl(url('/api/transfer'));
    req.add(const [1, 2, 3]);
    final resp = await req.close();
    expect(resp.statusCode, 400);
  });

  test('POST /api/transfer with an unknown id is a 403', () async {
    final req = await client.postUrl(url('/api/transfer'));
    req.headers
      ..set('x-transfer-id', 'nope')
      ..set('x-transfer-attempt', 'a1')
      ..set('x-file-size', '3');
    req.add(const [1, 2, 3]);
    final resp = await req.close();
    expect(resp.statusCode, 403);
  });

  // POST/GET 둘 다 attempt와 선언 크기 헤더가 필수: 하나라도
  // 없거나 파싱이 안 되면 registry(슬롯/토큰 소비)까지 가기 전에 400
  group('required transfer headers', () {
    Future<int> post(Map<String, String> headers) async {
      final req = await client.postUrl(url('/api/transfer'));
      headers.forEach(req.headers.set);
      req.add(const [1, 2, 3]);
      final resp = await req.close();
      await resp.drain<void>();
      return resp.statusCode;
    }

    Future<int> get(Map<String, String> headers) async {
      final req = await client.getUrl(url('/api/download/nope'));
      headers.forEach(req.headers.set);
      final resp = await req.close();
      await resp.drain<void>();
      return resp.statusCode;
    }

    test('POST without x-transfer-attempt or x-file-size is a 400', () async {
      expect(await post({'x-transfer-id': 'nope', 'x-file-size': '3'}), 400);
      expect(
        await post({'x-transfer-id': 'nope', 'x-transfer-attempt': 'a1'}),
        400,
      );
      expect(
        await post({
          'x-transfer-id': 'nope',
          'x-transfer-attempt': 'a1',
          'x-file-size': 'three',
        }),
        400,
      );
    });

    test('GET without x-transfer-attempt or x-file-size is a 400', () async {
      expect(await get({'x-file-size': '3'}), 400);
      expect(await get({'x-transfer-attempt': 'a1'}), 400);
      expect(
        await get({'x-transfer-attempt': 'a1', 'x-file-size': '3.5'}),
        400,
      );
    });

    test(
      'GET/POST with every header but an unknown transfer stay 404/403',
      () async {
        expect(
          await get({'x-transfer-attempt': 'a1', 'x-file-size': '3'}),
          404,
        );
      },
    );
  });

  test('an unknown route is a 404', () async {
    final resp = await (await client.getUrl(
      url('/definitely-not-here'),
    )).close();
    expect(resp.statusCode, 404);
  });

  test('a plain GET /ws (no upgrade headers) is a 404', () async {
    final resp = await (await client.getUrl(url('/ws'))).close();
    expect(resp.statusCode, 404);
  });

  test('WebSocket registration failure is reported and cleaned up', () async {
    registry.debugCreateSession = () async => throw StateError('no keys');
    try {
      final socket = await WebSocket.connect(
        'ws://${bound.host}:${bound.port}/ws',
      );
      await socket.drain<void>().timeout(const Duration(seconds: 3));
      expect(inboundErrors, hasLength(1));
      expect(inboundErrors.single, isA<StateError>());
      expect(store.conversations, isEmpty);
    } finally {
      registry.debugCreateSession = CryptoEngine().createSession;
    }
  });

  test('external origins receive no CORS or PNA permission', () async {
    final req = await client.getUrl(url('/health'));
    req.headers.set('origin', 'https://example.com');
    final resp = await req.close();
    await resp.drain<void>();
    expect(resp.headers.value('access-control-allow-origin'), isNull);
    expect(resp.headers.value('access-control-allow-private-network'), isNull);

    final preflight = await client.openUrl('OPTIONS', url('/api/transfer'));
    preflight.headers.set('origin', 'https://example.com');
    final denied = await preflight.close();
    await denied.drain<void>();
    expect(denied.statusCode, 404);
  });
}
