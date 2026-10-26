part of 'network_guard.dart';

// 이 클라이언트가 여는 소켓은 리다이렉트까지 전부 여길 지나감. 호스트명은 DNS도 안 묻고 거부함
@visibleForTesting
Future<ConnectionTask<Socket>> peerConnectionFactory(
  Uri uri,
  String? proxyHost,
  int? proxyPort,
) async {
  final address = InternetAddress.tryParse(uri.host);
  if (address == null) {
    throw SecurityException('refusing to resolve hostname "${uri.host}"');
  }
  NetworkGuard.assertReachable(address);
  return Socket.startConnect(address, uri.port);
}

HttpClient createPeerHttpClientImpl({Socket Function(Socket)? wrap}) {
  return HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..connectionFactory = wrap == null
        ? peerConnectionFactory
        : (uri, proxyHost, proxyPort) async {
            final task = await peerConnectionFactory(uri, proxyHost, proxyPort);
            return ConnectionTask.fromSocket(
              task.socket.then(wrap),
              task.cancel,
            );
          }
    ..findProxy = (_) => 'DIRECT';
}
