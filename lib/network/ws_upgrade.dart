import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;

import 'capped_socket.dart';

// shelf_web_socket webSocketHandler와 같은 헤더 검사·101 응답. 다른 점은 업그레이드한 소켓을 CappedSocket으로 감싸 메시지가 다 모이기 전에 상한을 거는 것
Response upgradeToCappedWebSocket(
  Request request, {
  required int Function(int messages) limit,
  required Duration pingInterval,
  required void Function(StreamChannel<dynamic> channel) onConnection,
}) {
  final upgrade = request.headers['Upgrade']?.toLowerCase();
  final connection = (request.headers['Connection'] ?? '')
      .toLowerCase()
      .split(',')
      .map((token) => token.trim());
  if (request.method != 'GET' ||
      upgrade != 'websocket' ||
      !connection.contains('upgrade')) {
    return Response.notFound(null);
  }
  final key = request.headers['Sec-WebSocket-Key'];
  if (request.headers['Sec-WebSocket-Version'] != '13' ||
      request.protocolVersion != '1.1' ||
      key == null) {
    return Response.badRequest(body: 'not a WebSocket 13 upgrade');
  }
  request.hijack((channel) {
    final socket = channel.sink;
    if (socket is! Socket) {
      throw ArgumentError('channel.sink must be a dart:io Socket');
    }
    socket.add(
      utf8.encode(
        'HTTP/1.1 101 Switching Protocols\r\n'
        'Upgrade: websocket\r\n'
        'Connection: Upgrade\r\n'
        'Sec-WebSocket-Accept: ${WebSocketChannel.signKey(key)}\r\n\r\n',
      ),
    );
    final capped = CappedSocket(socket, limit);
    final webSocket = WebSocket.fromUpgradedSocket(capped, serverSide: true)
      ..pingInterval = pingInterval;
    onConnection(cappedChannel(webSocket, capped));
  });
}
