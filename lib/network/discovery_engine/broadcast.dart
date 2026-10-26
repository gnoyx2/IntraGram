part of '../discovery_engine.dart';

typedef _BroadcastSpec = ({
  String peerId,
  String alias,
  String platform,
  int port,
  bool hostsRoom,
  bool inRoom,
});

// 테스트에서 네이티브 mDNS 채널 없이 광고 시작·정지 순서와 동시성을 검증하는 얇은 핸들
@visibleForTesting
abstract interface class BroadcastSession {
  Future<void> initialize();
  Future<void> start();
  Future<void> stop();
}

class _BonsoirBroadcastSession implements BroadcastSession {
  _BonsoirBroadcastSession(BonsoirService service)
    : _inner = BonsoirBroadcast(service: service);

  final BonsoirBroadcast _inner;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> stop() => _inner.stop();
}

extension _DiscoveryBroadcast on DiscoveryController {
  _BroadcastSpec? _desiredBroadcastSpec() {
    final identity = _identity;
    final port = _port;
    if (!_advertising || identity == null || port == null) return null;
    return (
      peerId: identity.peerId,
      alias: identity.alias,
      platform: identity.platform,
      port: port,
      hostsRoom: _hostsRoom,
      inRoom: _inRoom,
    );
  }

  BonsoirService _serviceFromSpec(_BroadcastSpec spec) => BonsoirService(
    name: 'IntraGram ${spec.alias}',
    type: kServiceType,
    port: spec.port,
    attributes: <String, String>{
      'id': spec.peerId,
      'alias': spec.alias,
      'os': spec.platform,
      'v': kProtocolVersion,
      if (spec.hostsRoom) 'room': '1',
      if (spec.inRoom) 'inRoom': '1',
    },
  );

  // 광고 시작·정지를 한 줄로 세움: Darwin bonsoir는 DNSServiceProcessResult를 메인 스레드에서 동기로 기다려서,
  // 이전 DNSServiceRef를 닫기 전에 같은 이름·포트로 두 번째 등록이 들어가면 mDNSResponder 응답 대기에 영구 정지(0x8BADF00D)함
  Future<void> _syncBroadcast() {
    final next = _broadcastSerial.then((_) => _syncBroadcastStep());
    _broadcastSerial = next.catchError((Object _) {});
    return next;
  }

  Future<void> _syncBroadcastStep() async {
    final desired = _desiredBroadcastSpec();
    if (desired == null) {
      await _stopActiveBroadcast();
      return;
    }
    if (_broadcast != null && _activeBroadcastSpec == desired) return;

    await _stopActiveBroadcast();

    // 기존 광고를 내리는 동안 stop·이름·방 힌트가 또 바뀌었을 수 있어 최신 목표를 다시 읽음
    final spec = _desiredBroadcastSpec();
    if (spec == null) return;

    final generation = _generation;
    BroadcastSession? broadcast;
    try {
      // mDNSResponder 연결이 막 죽은 순간(Wi-Fi를 갈아탄 직후 DefunctConnection)엔 initialize부터 던짐. 안 잡으면 앱이 죽어서 광고 실패는 삼키고 다음 start가 복구함
      broadcast = DiscoveryController.createBroadcast(_serviceFromSpec(spec));
      await broadcast.initialize();
      if (generation != _generation || !_advertising) {
        await _stopQuietly(broadcast);
        return;
      }
      await broadcast.start();
      if (generation != _generation || !_advertising) {
        await _stopQuietly(broadcast);
        return;
      }
      _broadcast = broadcast;
      _activeBroadcastSpec = spec;
    } on Object {
      // 반쯤 만든 인스턴스는 안 남김
      await _stopQuietly(broadcast);
      _broadcast = null;
      _activeBroadcastSpec = null;
    }
  }

  Future<void> _stopActiveBroadcast() async {
    final active = _broadcast;
    _broadcast = null;
    _activeBroadcastSpec = null;
    await _stopQuietly(active);
  }

  Future<void> _stopQuietly(BroadcastSession? session) async {
    if (session == null) return;
    try {
      await session.stop();
    } on Object {
      // 이미 닫혔거나 채널이 내려간 경우 정리 경로를 막지 않음
    }
  }
}
