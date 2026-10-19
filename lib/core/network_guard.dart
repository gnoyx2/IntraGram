import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

part 'network_guard_client.dart';

// 로컬 링크 밖 주소에 닿으려는 코드가 있을 때 던짐 (패킷이 공용 인터넷으로 나가면 안 됨)
class SecurityException implements Exception {
  SecurityException(this.message);
  final String message;
  @override
  String toString() => 'SecurityException: $message';
}

// 에어갭 강제: 주소 분류기를 일부러 단순하게 유지함. 정규식/플랫폼 파서 대신
// 정수 4개로 파싱해서 범위를 직접 비교함 (_octets 참고)
final class NetworkGuard {
  const NetworkGuard._();

  // 172 대역은 /8이 아니라 16..31만 사설임. 172.15.x.x, 172.32.x.x는 공인이라
  // o[0] == 172만 보면 인터넷으로 샘
  static bool isRfc1918(String ip) {
    final o = _octets(ip);
    if (o == null) return false;
    if (o[0] == 10) return true;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
    if (o[0] == 192 && o[1] == 168) return true;
    return false;
  }

  // 로컬 링크를 물리적으로 못 벗어나는 주소: RFC 1918 + 루프백 + APIPA(169.254/16)
  // IPv6는 _isIpv6LocalOnly 참고. 나머지는 전부 WAN 취급
  static bool isLinkLocalOrPrivate(String ip) {
    if (ip.contains(':')) return _isIpv6LocalOnly(ip);
    if (isRfc1918(ip)) return true;
    final o = _octets(ip);
    if (o == null) return false;
    if (o[0] == 127) return true;
    if (o[0] == 169 && o[1] == 254) return true;
    return false;
  }

  // IPv6는 루프백(::1)과 ULA(fc00::/7)만 인정함. GUA는 전역 라우팅이 가능해서
  // 로컬로 취급하면 에어갭이 깨지므로 일부러 거부함
  // 링크로컬(fe80::/10)도 제외: 스코프 ID(%en0) 없인 다이얼이 안 되는데
  // discovery/QR 경로가 아직 스코프 ID를 안 실음. 알려진 한계
  static bool _isIpv6LocalOnly(String ip) {
    if (ip == '::1') return true;
    final firstColon = ip.indexOf(':');
    if (firstColon <= 0) return false;
    final firstHextet = int.tryParse(ip.substring(0, firstColon), radix: 16);
    if (firstHextet == null) return false;
    return (firstHextet & 0xfe00) == 0xfc00; // fc00::/7
  }

  // IPv6는 대괄호로 감쌈. 안 그러면 주소의 ':'가 포트 구분자와 헷갈려 URL이 깨짐
  // 문자열 보간으로 ws:// URL을 짤 때 필요함 (Uri(host:)는 알아서 감쌈)
  static String hostForUri(String ip) => ip.contains(':') ? '[$ip]' : ip;

  // dotted-quad를 0..255 정수 4개로 파싱, 아니면 null. 정규식 대신 직접 비교하는 이유:
  // 0x7f.0.0.1/2130706433/127.1은 호출 전에 InternetAddress.tryParse가
  // 거부하고, 0177.0.0.1은 int.tryParse가 10진수 177로 읽어
  // 공인으로 분류돼 차단됨 (선행 0은 주소를 더 공인처럼 보이게만 해서 닫힌 쪽으로 실패)
  static List<int>? _octets(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return null;
      out.add(v);
    }
    return out;
  }

  // http(s)://<사설 IPv4>:<포트>만 통과하고 나머지는 null
  // connectManual도 같은 검사를 하지만 여기서 걸러야 "로컬 주소가 아님"을 보여줄 수 있음
  static ({String host, int port})? parsePeerQr(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (!uri.hasPort || uri.port == 0) return null;
    if (uri.userInfo.isNotEmpty) return null;
    return parsePeerEndpoint(uri.host, uri.port);
  }

  // 피어 다이얼 전용 단일 입구: 정규 dotted-decimal IPv4 + RFC 1918 + 포트 1..65535만 통과
  // 각 octet을 파싱한 뒤 다시 이어붙여 원본과 같은지 확인함. 선행 0(010 등)은 WHATWG URL이
  // octal로 재해석해 다른 주소가 되므로 규칙과 무관하게 걸러냄
  // loopback/APIPA/IPv6 ULA는 peer 주소로 안 받음 (내부 loopback 예외는 외부 입력으로 선택 불가여야 함)
  static ({String host, int port})? parsePeerEndpoint(String host, int port) {
    if (port < 1 || port > 65535) return null;
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octetPattern = RegExp(r'^(0|[1-9][0-9]{0,2})$');
    final octets = <int>[];
    for (final part in parts) {
      if (!octetPattern.hasMatch(part)) return null;
      final value = int.parse(part);
      if (value > 255) return null;
      octets.add(value);
    }
    final canonical = octets.join('.');
    if (canonical != host || !isRfc1918(canonical)) return null;
    return (host: canonical, port: port);
  }

  // IPv4/IPv6 둘 다 받되 판정은 isLinkLocalOrPrivate 하나로 통일. IPv6 GUA는 거기서 이미 거부됨
  static void assertReachable(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4 &&
        address.type != InternetAddressType.IPv6) {
      throw SecurityException('blocked non-IP target ${address.address}');
    }
    if (!isLinkLocalOrPrivate(address.address)) {
      throw SecurityException('blocked WAN target ${address.address}');
    }
  }

  // 우선순위: 진짜 LAN(192.168 > 10 > 172.16/12), 그다음 APIPA. 루프백은 후보에서 뺌:
  // 서버가 루프백에 바인딩되면 다른 기기는 못 닿는데 isRunning은 true라 피어 목록/QR이 죽은 주소를 흘림
  // 네트워크가 없으면 null (ServerController.start가 에러로 보여주고 시작 거부)
  // 루프백을 후보에 넣으면 이 "네트워크 없음" 경로가 영영 안 뚫림
  static Future<InternetAddress?> localBindAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: true,
    );
    final picked = pickBindAddress([
      for (final iface in interfaces)
        for (final addr in iface.addresses) (iface.name, addr),
    ]);
    if (picked != null) return picked;

    // IPv4 LAN이 없으면 IPv6 ULA로 폴백 (예: 상류 백홀이 IPv6 전용인 네트워크)
    // 링크로컬은 스코프 ID 없이 다이얼이 안 돼서 제외
    final ipv6 = await NetworkInterface.list(
      type: InternetAddressType.IPv6,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final iface in ipv6) {
      for (final addr in iface.addresses) {
        if (_isIpv6LocalOnly(addr.address)) return addr;
      }
    }
    return null;
  }

  // 바인드할 LAN 주소가 없을 때, 기기가 대신 가진 공인·CGNAT IPv4 (없으면 진짜로 네트워크가 없음)
  static Future<String?> nonPrivateIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return firstNonPrivate([
      for (final iface in interfaces)
        for (final addr in iface.addresses) addr.address,
    ]);
  }

  @visibleForTesting
  static String? firstNonPrivate(Iterable<String> addresses) {
    for (final ip in addresses) {
      if (_octets(ip) != null && !_isBindableLan(ip)) return ip;
    }
    return null;
  }

  static bool _isBindableLan(String ip) {
    if (isRfc1918(ip)) return true;
    final o = _octets(ip);
    return o != null && o[0] == 169 && o[1] == 254;
  }

  // 최초 호스트 검사만으론 부족함: HttpClient는 3xx를 따라가고 WebSocket.connect도
  // 내부적으로 HTTP 업그레이드를 씀. 이 클라이언트가 여는 모든 소켓(리다이렉트 포함)을
  // connectionFactory 한 곳에서 재검증함 (network_guard_client.dart)
  // wrap은 연결된 소켓을 한 번 감쌀 기회 (피어 다이얼이 수신 바이트 상한을 거는 데 씀)
  static HttpClient createPeerHttpClient({Socket Function(Socket)? wrap}) =>
      createPeerHttpClientImpl(wrap: wrap);

  // 사설 주소가 여러 인터페이스에 있으면 이름으로 진짜 Wi-Fi·이더넷을 먼저 고름. 대역 순위만 보면 Mac의
  // VM·테더링 브리지(bridge100·vmnet·vnic), VPN(utun), 셀룰러(pdp_ip·rmnet)가 받은 10.x·192.168.x에
  // 바인드해서 QR·포털 주소가 LAN 상대가 못 닿는 주소가 됨. 링크로컬(169.254)은 인터페이스와 무관하게 마지막
  // 이름 규칙에 없는 인터페이스는 그 사이 (Android 핫스팟 swlan0, iPhone 핫스팟 bridge100은 혼자면 그대로 고름)
  @visibleForTesting
  static InternetAddress? pickBindAddress(
    Iterable<(String, InternetAddress)> candidates,
  ) {
    final lan = [
      for (final (name, addr) in candidates)
        if (_isBindableLan(addr.address)) (name, addr),
    ];
    if (lan.isEmpty) return null;
    int key((String, InternetAddress) c) =>
        (_rank(c.$2.address) == 3 ? 100 : 0) +
        _interfaceClass(c.$1) * 10 +
        _rank(c.$2.address);
    lan.sort((a, b) => key(a).compareTo(key(b)));
    return lan.first.$2;
  }

  static final RegExp _physicalInterface = RegExp(
    r'^(en\d|eth|wlan|wlp|enp|eno|ens|wi-?fi|ethernet|이더넷|local area)',
    caseSensitive: false,
  );
  static final RegExp _virtualInterface = RegExp(
    r'^(bridge|vmnet|vnic|utun|pdp_ip|rmnet|ccmni|v4-|tun|tap|ppp|ipsec|'
    r'vboxnet|docker|br-|veth|virbr|zt|tailscale|wg|awdl|llw|anpi|ap\d|'
    r'vethernet)|virtualbox|vmware|hyper-v|bluetooth',
    caseSensitive: false,
  );

  static int _interfaceClass(String name) {
    if (_virtualInterface.hasMatch(name)) return 2;
    return _physicalInterface.hasMatch(name) ? 0 : 1;
  }

  static int _rank(String ip) {
    final o = _octets(ip);
    if (o == null) return 99;
    if (o[0] == 192 && o[1] == 168) return 0;
    if (o[0] == 10) return 1;
    if (o[0] == 172) return 2;
    if (o[0] == 169 && o[1] == 254) return 3;
    return 9;
  }
}
