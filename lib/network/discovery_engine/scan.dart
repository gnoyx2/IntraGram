part of '../discovery_engine.dart';

extension _DiscoveryScan on DiscoveryController {
  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // resolve가 주소와 TXT를 채워 줌
        final resolver = _discovery?.serviceResolver;
        if (resolver != null) service.resolve(resolver);
      case BonsoirDiscoveryServiceResolvedEvent(:final service):
        _addResolved(service);
      case BonsoirDiscoveryServiceLostEvent(:final service):
        _removeByServiceName(service.name);
      default:
        break;
    }
  }

  // eventStream이 나중에 오류를 흘림 (같은 DefunctConnection). 안 잡으면 앱이 죽어서 스캔만 포기하고 isRunning을 내림 (새로고침이나 다음 start가 복구)
  void _onDiscoveryError() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _discovery = null;
  }

  void _addResolved(BonsoirService service) {
    final peer = peerFromBonsoirService(service, selfPeerId: _selfPeerId);
    if (peer == null) return;
    _peers[peer.peerId] = peer;
    _serviceNames[peer.peerId] = service.name;
    _publish();
  }

  // name이 지금도 누군가의 최신 name일 때만 지움 (옛 이름의 늦은 goodbye는 무시)
  void _removeByServiceName(String name) {
    for (final entry in _serviceNames.entries) {
      if (entry.value != name) continue;
      _serviceNames.remove(entry.key);
      if (_peers.remove(entry.key) != null) _publish();
      return;
    }
  }

  void _sweepStale() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere((peerId, peer) {
      final stale = isDiscoveryPeerStale(peer.seenAt, now);
      if (stale) _serviceNames.remove(peerId);
      return stale;
    });
    if (_peers.length != before) _publish();
  }
}

// 자기 자신이거나 주소가 로컬 밖이면(아직 resolve 전이어도) null. 순수 함수라 mDNS 없이 테스트됨
@visibleForTesting
PeerDevice? peerFromBonsoirService(
  BonsoirService service, {
  required String? selfPeerId,
}) {
  final attributes = service.attributes;
  final peerId = attributes['id'] ?? service.name;
  if (peerId == selfPeerId) return null;

  final host = service.host;
  if (host == null || !NetworkGuard.isLinkLocalOrPrivate(host)) {
    return null;
  }

  return PeerDevice(
    peerId: peerId,
    alias: attributes['alias'] ?? service.name,
    platform: wirePlatform(attributes['os']),
    host: host,
    port: service.port,
    seenAt: DateTime.now(),
    hostsRoom: attributes['room'] == '1',
    inRoom: attributes['inRoom'] == '1',
  );
}

// 새로고침 주기의 3배 동안 소식이 없으면 stale
@visibleForTesting
bool isDiscoveryPeerStale(DateTime seenAt, DateTime now) =>
    seenAt.isBefore(now.subtract(kDiscoveryRefresh * 3));

extension BonsoirServiceHost on BonsoirService {
  // 다이얼할 IPv4를 고름 (resolve 전이면 null). Apple은 IPv6 링크로컬을 먼저 주기도 하고 같은 기기 등록이면 127.0.0.1이 앞에 붙어서
  // RFC1918 주소를 먼저 보고 loopback은 마지막에
  String? get host {
    final ipv4 = hostAddresses.where((a) => a.isNotEmpty && !a.contains(':'));
    for (final address in ipv4) {
      if (NetworkGuard.isRfc1918(address)) return address;
    }
    for (final address in ipv4) {
      if (address != '127.0.0.1') return address;
    }
    for (final address in ipv4) {
      return address;
    }
    for (final address in hostAddresses) {
      if (address.isNotEmpty) return address;
    }
    return null;
  }
}
