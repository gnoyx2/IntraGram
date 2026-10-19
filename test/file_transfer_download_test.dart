import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/file_streamer.dart';

void main() {
  group('FileStreamer.download — group-room member-to-member pull', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('intragram_dl'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('pulls bytes from a peer /api/download and writes them', () async {
      final payload = List<int>.filled(20000, 42);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response
            ..statusCode = HttpStatus.ok
            ..add(payload);
          await req.response.close();
        }),
      );

      final dest = '${dir.path}/pulled.bin';
      final written = await FileStreamer.download(
        host: server.address.address,
        port: server.port,
        transferId: 't1',
        attemptId: 'a1',
        authToken: 'tok-t1',
        destinationPath: dest,
        declaredSize: payload.length,
      );

      expect(written, payload.length);
      expect(File(dest).readAsBytesSync(), payload);
    });

    test('refuses a WAN source address before dialling', () async {
      await expectLater(
        FileStreamer.download(
          host: '8.8.8.8',
          port: 7890,
          transferId: 't2',
          attemptId: 'a2',
          authToken: 'tok-t2',
          destinationPath: '${dir.path}/nope.bin',
          declaredSize: 1,
        ),
        throwsA(isA<SecurityException>()),
      );
      expect(File('${dir.path}/nope.bin').existsSync(), isFalse);
    });

    test('does not follow a 302 redirect to a WAN address — Dart HttpClient '
        'follows redirects by default, which would otherwise dial whatever '
        'host the "peer" names', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set('location', 'http://8.8.8.8/payload');
          await req.response.close();
        }),
      );

      await expectLater(
        FileStreamer.download(
          host: server.address.address,
          port: server.port,
          transferId: 'r1',
          attemptId: 'ar1',
          authToken: 'tok-r1',
          destinationPath: '${dir.path}/redirected.bin',
          declaredSize: 1,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(File('${dir.path}/redirected.bin').existsSync(), isFalse);
    });

    test('a non-200 response fails the pull', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }),
      );

      await expectLater(
        FileStreamer.download(
          host: server.address.address,
          port: server.port,
          transferId: 'gone',
          attemptId: 'agone',
          authToken: 'tok-gone',
          destinationPath: '${dir.path}/missing.bin',
          declaredSize: 10,
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('FileStreamer.downloadToMemory — RAM-only voice pull', () {
    test('pulls bytes from a peer /api/download into memory', () async {
      final payload = List<int>.filled(12000, 9);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response
            ..statusCode = HttpStatus.ok
            ..add(payload);
          await req.response.close();
        }),
      );

      final bytes = await FileStreamer.downloadToMemory(
        host: server.address.address,
        port: server.port,
        transferId: 'v1',
        attemptId: 'av1',
        authToken: 'tok-v1',
        declaredSize: payload.length,
      );
      expect(bytes, payload);
    });

    test('does not follow a 302 redirect to a WAN address', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set('location', 'http://8.8.8.8/payload');
          await req.response.close();
        }),
      );

      await expectLater(
        FileStreamer.downloadToMemory(
          host: server.address.address,
          port: server.port,
          transferId: 'r2',
          attemptId: 'ar2',
          authToken: 'tok-r2',
          declaredSize: 1,
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('refuses a WAN source address before dialling', () async {
      await expectLater(
        FileStreamer.downloadToMemory(
          host: '8.8.8.8',
          port: 7890,
          transferId: 'v2',
          attemptId: 'av2',
          authToken: 'tok-v2',
          declaredSize: 1,
        ),
        throwsA(isA<SecurityException>()),
      );
    });

    test('aborts when the body exceeds the declared size', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((req) async {
          req.response
            ..statusCode = HttpStatus.ok
            ..add(List<int>.filled(5 * 1024 * 1024, 1));
          try {
            await req.response.close();
          } on Object {
            // 클라이언트가 먼저 끊는 게 의도된 상황
          }
        }),
      );

      await expectLater(
        FileStreamer.downloadToMemory(
          host: server.address.address,
          port: server.port,
          transferId: 'v3',
          attemptId: 'av3',
          authToken: 'tok-v3',
          declaredSize: 1024, // 피어는 1 KB라 해놓고 5 MB를 보냄
        ),
        throwsA(isA<SecurityException>()),
      );
    });
  });

  // GET 요청은 토큰/attempt/선언 크기를 헤더로 실어야 서버가 슬롯을 소비하기 전에 검증할 수 있음
  test('download and downloadToMemory send token, attempt and size', () async {
    final seen = <HttpHeaders>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((req) async {
        seen.add(req.headers);
        req.response.add(List<int>.filled(64, 1));
        await req.response.close();
      }),
    );
    final dir = Directory.systemTemp.createTempSync('intragram_hdr');
    addTearDown(() => dir.deleteSync(recursive: true));
    await FileStreamer.download(
      host: server.address.address,
      port: server.port,
      transferId: 't',
      attemptId: 'att-1',
      authToken: 'tok-1',
      destinationPath: '${dir.path}/x.bin',
      declaredSize: 64,
    );
    await FileStreamer.downloadToMemory(
      host: server.address.address,
      port: server.port,
      transferId: 'v',
      attemptId: 'att-2',
      authToken: 'tok-2',
      declaredSize: 64,
    );
    for (final (i, want) in [('tok-1', 'att-1'), ('tok-2', 'att-2')].indexed) {
      expect(seen[i].value('x-transfer-token'), want.$1);
      expect(seen[i].value('x-transfer-attempt'), want.$2);
      expect(seen[i].value('x-file-size'), '64');
    }
  });
}
