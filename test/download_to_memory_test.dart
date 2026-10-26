import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'package:intragram/network/crypto_engine.dart';
import 'package:intragram/network/file_streamer.dart';
import 'package:intragram/network/file_transfer_crypto.dart';

import 'support/file_transfer_crypto_pair.dart';

// FileStreamer.downloadToMemory(음성 수신용 RAM 다운로드): 공개 진입점에서
// 상한(kMaxVoiceNoteBytes) 강제, 선언한 크기를 못 채운 짧은 EOF 거부,
// 정지한 응답 앞에서도 취소가 곧바로 끝남

void main() {
  late HttpServer server;
  var requests = 0;
  // 요청마다 응답을 만드는 핸들러 (테스트가 바꿔 끼움)
  late Future<void> Function(HttpRequest request) handler;

  setUp(() async {
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        requests++;
        try {
          await handler(request);
        } on Object {
          // 클라이언트가 먼저 끊은 경우
        }
      }),
    );
  });
  tearDown(() => server.close(force: true));

  Future<Uint8List> download(
    int declaredSize, {
    OpenChunk? decrypt,
    CancelToken? cancelToken,
    int? maxBytes,
  }) => FileStreamer.downloadToMemory(
    host: server.address.address,
    port: server.port,
    transferId: testTransferId,
    attemptId: testAttemptId,
    authToken: 'tok',
    declaredSize: declaredSize,
    decrypt: decrypt,
    cancelToken: cancelToken,
    maxBytes: maxBytes ?? kMaxVoiceNoteBytes,
  );

  Future<void> respondWith(HttpRequest request, List<int> body) async {
    request.response.add(body);
    await request.response.close();
  }

  test('returns exactly the declared bytes', () async {
    handler = (r) => respondWith(r, List<int>.filled(100, 7));
    expect(await download(100), List<int>.filled(100, 7));
  });

  test('a short EOF is rejected, never returned as a shorter clip', () async {
    handler = (r) => respondWith(r, List<int>.filled(60, 7));
    await expectLater(download(100), throwsA(isA<SecurityException>()));
  });

  test('a body larger than declared is rejected', () async {
    handler = (r) => respondWith(r, List<int>.filled(101, 7));
    await expectLater(download(100), throwsA(isA<SecurityException>()));
  });

  test('a declared size over the voice limit is refused before any '
      'request is made', () async {
    handler = (r) => respondWith(r, const []);

    await expectLater(
      download(kMaxVoiceNoteBytes + 1),
      throwsA(isA<SecurityException>()),
    );

    expect(requests, 0, reason: 'refused at the public entry, no socket');
  });

  test('the limit is caller-tunable and inclusive', () async {
    handler = (r) => respondWith(r, List<int>.filled(10, 1));
    expect(await download(10, maxBytes: 10), hasLength(10));
    await expectLater(
      download(11, maxBytes: 10),
      throwsA(isA<SecurityException>()),
    );
  });

  test('a truncated encrypted body is rejected', () async {
    final (a, b) = await pairSessions();
    final wire = await encryptForTest(a, Uint8List(64));
    handler = (r) => respondWith(r, wire.sublist(0, wire.length - 3));

    await expectLater(
      download(64, decrypt: b.openBytes),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'cancel on a stalled response ends promptly as a cancellation',
    () async {
      final stall = Completer<void>();
      handler = (r) async {
        r.response.add(List<int>.filled(3, 1)); // 100바이트 중 3바이트 주고 멈춤
        await r.response.flush();
        await stall.future;
      };
      final token = CancelToken();
      final outcome = download(
        100,
        cancelToken: token,
      ).then<Object?>((_) => null, onError: (Object e) => e);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final watch = Stopwatch()..start();
      token.cancel();
      final error = await outcome;
      stall.complete();

      expect(error, isA<TransferCancelledException>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  // 2 MiB를 넘는 음성은 레코드 둘로 옴: 받은 조각은 결과로 옮긴 뒤 덮어써서 성공하든 실패하든 RAM에 사본이 안 남음
  group('received audio pieces are overwritten', () {
    const size = kFileChunkBytes + 64;
    late List<Uint8List> opened;
    late OpenChunk open;
    late List<int> wire;

    setUp(() async {
      final (a, b) = await pairSessions();
      wire = await encryptForTest(a, Uint8List(size)..fillRange(0, size, 9));
      opened = <Uint8List>[];
      open =
          ({
            required nonce,
            required cipher,
            required mac,
            required aad,
          }) async {
            final plain = await b.openBytes(
              nonce: nonce,
              cipher: cipher,
              mac: mac,
              aad: aad,
            );
            opened.add(plain);
            return plain;
          };
    });

    test('after a pull that fails partway', () async {
      handler = (r) => respondWith(r, wire.sublist(0, wire.length - 3));
      await expectLater(
        download(size, decrypt: open, maxBytes: size),
        throwsA(isA<FormatException>()),
      );
      expect(opened, hasLength(1));
      expect(opened.single.every((byte) => byte == 0), isTrue);
    });

    test('after a pull that succeeds', () async {
      handler = (r) => respondWith(r, wire);
      final bytes = await download(size, decrypt: open, maxBytes: size);
      expect(bytes.every((byte) => byte == 9), isTrue);
      expect(opened, hasLength(2));
      for (final piece in opened) {
        expect(piece.every((byte) => byte == 0), isTrue);
      }
    });
  });
}
