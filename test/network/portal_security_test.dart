import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/app_identity.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/link_registry.dart';
import 'package:intragram/network/local_server.dart';
import 'package:intragram/store/in_memory_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'portal policy permits bundled blocks and rejects foreign Host on every route',
    () async {
      final store = InMemoryStore();
      final identity = AppIdentity(
        peerId: '0' * 32,
        alias: 'test',
        platform: 'Linux',
      );
      final registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: identity,
      );
      final server = LocalServer(
        registry: registry,
        identity: identity,
        onInboundError: (e, s) => fail('$e'),
        preferredPort: 0,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      final client = HttpClient();
      try {
        final bound = (await server.start())!;
        final base = 'http://${bound.host}:${bound.port}';
        for (final path in [
          '/',
          '/health',
          '/missing',
          '/api/download/x',
          '/ws',
        ]) {
          final response = await (await client.getUrl(
            Uri.parse('$base$path'),
          )).close();
          final body = await utf8.decoder.bind(response).join();
          expect(response.headers.value('x-frame-options'), 'DENY');
          expect(response.headers.value('x-content-type-options'), 'nosniff');
          expect(response.headers.value('referrer-policy'), 'no-referrer');
          expect(response.headers.value('cache-control'), 'no-store');
          expect(response.headers.value('x-powered-by'), isNull);
          expect(
            response.headers.value('permissions-policy'),
            contains('camera=()'),
          );
          expect(
            response.headers.value('cross-origin-opener-policy'),
            'same-origin',
          );
          expect(
            response.headers.value('cross-origin-resource-policy'),
            'same-origin',
          );
          final policy = response.headers.value('content-security-policy')!;
          for (final directive in [
            "default-src 'none'",
            "connect-src 'self'",
            "frame-ancestors 'none'",
            "base-uri 'none'",
            "form-action 'none'",
          ]) {
            expect(policy, contains(directive));
          }
          if (path == '/') {
            // 옛 WebKit은 'self'를 ws:에 안 맞춤: 웹소켓 주소를 명시함
            expect(
              policy,
              contains("connect-src 'self' ws://${bound.host}:${bound.port}"),
            );
            expect(body, contains('href="data:image/svg+xml,'));
            expect(
              body,
              contains(
                'content="#EEF2F6" media="(prefers-color-scheme: light)"',
              ),
            );
            expect(
              body,
              contains(
                'content="#10141B" media="(prefers-color-scheme: dark)"',
              ),
            );
            for (final tag in ['script', 'style']) {
              final block = RegExp(
                '<$tag>([\\s\\S]*?)</$tag>',
              ).firstMatch(body)!.group(1)!;
              final hash = await Sha256().hash(utf8.encode(block));
              expect(
                policy,
                contains("$tag-src 'sha256-${base64Encode(hash.bytes)}'"),
              );
            }
          }
        }
        for (final path in [
          '/',
          '/health',
          '/api/transfer',
          '/api/download/x',
          '/ws',
        ]) {
          for (final host in [
            'evil.example:${bound.port}',
            bound.host,
            '${bound.host}:1',
          ]) {
            final request = await client.getUrl(Uri.parse('$base$path'));
            request.headers.set('host', host);
            final response = await request.close();
            await response.drain<void>();
            expect(response.statusCode, 421, reason: '$path $host');
            expect(
              response.headers.value('content-security-policy'),
              isNotNull,
            );
          }
        }
      } finally {
        client.close(force: true);
        await server.stop();
        await registry.disposeAll();
        store.dispose();
      }
    },
  );

  test(
    'a request naming another host, or one that never ends, is dropped',
    () async {
      final store = InMemoryStore();
      final identity = AppIdentity(
        peerId: '0' * 32,
        alias: 'test',
        platform: 'Linux',
      );
      final registry = LinkRegistry(
        store: store,
        crypto: CryptoEngine(),
        identity: identity,
      );
      final server = LocalServer(
        registry: registry,
        identity: identity,
        onInboundError: (e, s) => fail('$e'),
        preferredPort: 0,
        bindAddress: InternetAddress.loopbackIPv4,
        idleTimeout: const Duration(milliseconds: 200),
      );
      try {
        final bound = (await server.start())!;
        final host = '${bound.host}:${bound.port}';
        Future<String> raw(String head) async {
          final socket = await Socket.connect(bound.host, bound.port);
          socket.write(head);
          return utf8.decoder
              .bind(socket)
              .join()
              .timeout(const Duration(seconds: 5));
        }

        const close = 'Connection: close\r\n\r\n';
        // absolute-form과 X-Forwarded-Host는 dart:io가 Host 대신 그쪽 호스트를 씀
        expect(
          await raw(
            'GET http://evil.example:${bound.port}/health HTTP/1.1\r\n'
            'Host: $host\r\n$close',
          ),
          startsWith('HTTP/1.1 400'),
        );
        expect(
          await raw(
            'GET /health HTTP/1.1\r\nHost: $host\r\n'
            'X-Forwarded-Host: evil.example\r\n$close',
          ),
          startsWith('HTTP/1.1 400'),
        );
        // 쉼표 목록 Host는 dart:io가 요청 URI를 못 만들어서 shelf에 닿기 전에 막아야 함 (500 아님)
        final comma = await raw(
          'GET /health HTTP/1.1\r\nHost: $host, evil.example\r\n$close',
        );
        expect(comma, startsWith('HTTP/1.1 400'));
        expect(comma.toLowerCase(), contains('x-frame-options: deny'));
        expect(
          await raw('GET /health HTTP/1.1\r\nHost: $host\r\n$close'),
          startsWith('HTTP/1.1 200'),
        );
        // 머리를 끝내지 않는 연결은 idleTimeout 뒤 닫힘 (기본 120초면 위 timeout에 걸림)
        expect(await raw('GET /health HTTP/1.1\r\nHost: $host\r\n'), isEmpty);
      } finally {
        await server.stop();
        await registry.disposeAll();
        store.dispose();
      }
    },
  );
}
