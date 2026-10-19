part of 'network_guard.dart';

// HttpClient.connectionFactory에 물리는 실제 검사. 리다이렉트(3xx)로 간 곳까지 이 클라이언트가 여는
// 모든 소켓이 여길 거침. 호스트명이면 DNS 조회조차 안 하고 거부함 (주소 정책을 resolver에 안 맡김)
// connectionFactory는 write-only라 다시 못 읽어서 top-level 함수로 뺌 (직접 테스트용)
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
