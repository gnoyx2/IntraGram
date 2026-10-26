part of '../discovery_engine.dart';

extension _DiscoveryBroadcast on DiscoveryController {
  BonsoirService _service(AppIdentity identity, int port) => BonsoirService(
    name: 'IntraGram ${identity.alias}',
    type: kServiceType,
    port: port,
    attributes: <String, String>{
      'id': identity.peerId,
      'alias': identity.alias,
      'os': identity.platform,
      'v': kProtocolVersion,
      if (_hostsRoom) 'room': '1',
      if (_inRoom) 'inRoom': '1',
    },
  );

  Future<void> _restartBroadcast() async {
    final identity = _identity;
    final port = _port;
    if (identity == null || port == null || !isRunning) return;
    await _broadcast?.stop();
    try {
      final broadcast = BonsoirBroadcast(service: _service(identity, port));
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
    } on Object {
      _broadcast = null;
    }
  }
}
