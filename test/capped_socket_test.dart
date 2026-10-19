import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:intragram/network/capped_socket.dart';
import 'package:intragram/store/models.dart';

// 웹소켓 메시지가 다 모이기 전에, 마지막 메시지 뒤로 들어온 바이트가 상한을 넘으면 소켓을 끊음
// (dart:io는 메시지 하나를 상한 없이 모은 뒤에야 앱에 넘김)
void main() {
  Future<(WebSocket server, WebSocket client, CappedSocket capped)> pair(
    int Function(int messages) limit,
  ) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    final accepted = listener.first;
    final raw = await Socket.connect(listener.address, listener.port);
    final capped = CappedSocket(await accepted, limit);
    final server = WebSocket.fromUpgradedSocket(capped, serverSide: true);
    final client = WebSocket.fromUpgradedSocket(raw, serverSide: false);
    addTearDown(() async {
      await client.close();
      await server.close();
    });
    return (server, client, capped);
  }

  test('an oversized first message is cut before it is assembled', () async {
    final (server, client, capped) = await pair((_) => 64 * 1024);
    final got = <Object?>[];
    final done = Completer<void>();
    server.listen(got.add, onDone: done.complete, onError: (_) {});
    client.add('x' * (1024 * 1024));
    await done.future.timeout(const Duration(seconds: 5));
    expect(got, isEmpty, reason: 'the 1 MiB message never reached the app');
  });

  test('the budget resets after every delivered message', () async {
    final (server, client, capped) = await pair((_) => 64 * 1024);
    final got = StreamController<String>();
    server.listen((m) {
      capped.messageReceived();
      got.add(m as String);
    });
    final received = StreamIterator(got.stream);
    // 한 번에 하나씩: 메시지마다 예산이 다시 차서 합이 64 KiB를 넘어도 끊기지 않음
    for (var i = 0; i < 4; i++) {
      client.add('y' * (40 * 1024));
      expect(
        await received.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
    }
    expect(capped.messages, 4);
  });

  test('the handshake budget is small, then the frame cap applies', () {
    expect(wireBudget(0, LargeMessageMode.inline), kHandshakeWireBytes);
    expect(
      wireBudget(1, LargeMessageMode.inline),
      greaterThan(kHandshakeWireBytes),
    );
    expect(
      wireBudget(5, LargeMessageMode.unlimited),
      greaterThan(wireBudget(5, LargeMessageMode.inline)),
    );
  });
}
