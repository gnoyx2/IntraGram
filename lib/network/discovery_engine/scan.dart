part of '../discovery_engine.dart';

extension _DiscoveryScan on DiscoveryController {
  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        // resolution이 호스트 주소랑 TXT 레코드를 채워줌
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

  // 광고/초기화가 끝난 뒤 eventStream 자체가 에러를 흘리는 경우
  // (같은 DefunctConnection이 이번엔 스트림 이벤트로 옴)
  // 안 잡으면 setup의 try/catch로 못 잡는 미처리 비동기 예외라 앱이 죽음
  // 스캔만 포기하고 isRunning을 정직하게 false로 내림 (새로고침 버튼/카운트다운이나 다음 start가 복구)
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

  // name이 지금도 어느 peerId의 현재 서비스 name일 때만 지움: rename으로 이미 밀려난 옛 name의
  // 뒤늦은 goodbye는 매치가 안 돼서 무시됨 (_serviceNames 참고)
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

// 자기 자신이거나 host가 로컬 링크 밖이면(또는 아직 resolve 안 됐으면) null. 상태를 안 건드리는 순수 함수라
// mDNS 데몬 없이 BonsoirService 인스턴스만 있으면 테스트 가능
@visibleForTesting
PeerDevice? peerFromBonsoirService(
  BonsoirService service, {
  required String? selfPeerId,
}) {
  final attributes = service.attributes;
  final peerId = attributes['id'] ?? service.name;
  if (peerId == selfPeerId) return null; // 자기 자신은 목록에 안 올림

  final host = service.host;
  if (host == null || !NetworkGuard.isLinkLocalOrPrivate(host)) {
    // resolve된 주소가 로컬 링크 밖이면 라우팅 가능한 타겟을 노출하느니 버림
    return null;
  }

  return PeerDevice(
    peerId: peerId,
    alias: attributes['alias'] ?? service.name,
    platform: attributes['os'] ?? 'Unknown',
    host: host,
    port: service.port,
    seenAt: DateTime.now(),
    hostsRoom: attributes['room'] == '1',
    inRoom: attributes['inRoom'] == '1',
  );
}

// 새로고침 주기의 3배 동안 소식이 없으면 stale. 순수 비교라 테스트에 고정 DateTime 두 개면 됨
@visibleForTesting
bool isDiscoveryPeerStale(DateTime seenAt, DateTime now) =>
    seenAt.isBefore(now.subtract(kDiscoveryRefresh * 3));

extension BonsoirServiceHost on BonsoirService {
  // 다이얼 가능한 IPv4를 고름 (아직 resolve 안 됐으면 null). Apple 스택은 IPv6
  // link-local을 먼저 주는 경우가 흔해서 첫 주소만 보면 멀쩡한 IPv4가 있어도 피어가 드롭됨
  // 같은 기기에서 register하면 127.0.0.1이 맨 앞에 얹히기도
  // 해서 RFC1918 실주소를 우선하고 loopback은 마지막 수단으로만
  // 씀
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
