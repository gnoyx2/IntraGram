part of '../server_controller.dart';

extension _ServerListener on ServerController {
  // 정지 중 OS가 리스닝 소켓을 거뒀는지 내 포트에만 연결해 확인함
  Future<bool> _listenerAlive() async {
    final host = _server?.boundHost;
    final port = _server?.boundPort;
    if (host == null || port == null) return false;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }
}
