import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart'
    show WebSocketChannel;

import 'capped_socket.dart';

// shelf_web_socket webSocketHandler와 동일한 헤더 검사 및 101 응답을 처리함. 업그레이드된 소켓을 CappedSocket으로 래핑하여 메시지가 수신 완료되기 전에 바이트 상한을 적용함
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
