import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

part 'network_guard_client.dart';

// 사설망 밖 연결이나 허용 경로 이탈(resolveWithin) 시 던짐
class SecurityException implements Exception {
  SecurityException(this.message);
  final String message;
  @override
  String toString() => 'SecurityException: $message';
}

// 앱이 여는 소켓을 사설 주소로만 보내는 분류기. 정규식 없이 옥텟 4개를 정수로 비교함
final class NetworkGuard {
  const NetworkGuard._();

  static bool isRfc1918(String ip) {
    final o = _octets(ip);
    if (o == null) return false;
    if (o[0] == 10) return true;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
    if (o[0] == 192 && o[1] == 168) return true;
    return false;
  }

  static bool isLinkLocalOrPrivate(String ip) {
    if (ip.contains(':')) return _isIpv6LocalOnly(ip);
    if (isRfc1918(ip)) return true;
    final o = _octets(ip);
    if (o == null) return false;
    if (o[0] == 127) return true;
    if (o[0] == 169 && o[1] == 254) return true;
    return false;
  }

  // IPv6는 ::1과 ULA(fc00::/7)만 로컬로 봄. GUA는 인터넷으로 라우팅되고, 링크로컬(fe80::/10)은
  // 스코프 ID(%en0) 없인 다이얼이 안 되는데 discovery·QR이 그걸 안 실음
  static bool _isIpv6LocalOnly(String ip) {
    if (ip == '::1') return true;
    final firstColon = ip.indexOf(':');
    if (firstColon <= 0) return false;
    final firstHextet = int.tryParse(ip.substring(0, firstColon), radix: 16);
    if (firstHextet == null) return false;
    return (firstHextet & 0xfe00) == 0xfc00; // fc00::/7
  }

  static String hostForUri(String ip) => ip.contains(':') ? '[$ip]' : ip;

  // 칸마다 10진 숫자만 받음: int.tryParse는 0x·부호·공백도 읽어서 0xa.0.0.1이 사설로 통과함.
  // 선행 0(0177)은 10진수로 읽혀 공인 쪽으로 빠짐 (닫힌 쪽 실패)
  static final RegExp _decimalOctet = RegExp(r'^\d{1,3}$');

  static List<int>? _octets(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final p in parts) {
      if (!_decimalOctet.hasMatch(p)) return null;
      final v = int.parse(p);
      if (v > 255) return null;
      out.add(v);
    }
    return out;
  }

  // QR 주소는 http(s)://<사설 IPv4>:<포트>만 받음. 스캔 화면에서 바로 '로컬 주소 아님'을 띄우려고 여기서 거름
  static ({String host, int port})? parsePeerQr(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (!uri.hasPort || uri.port == 0) return null;
    if (uri.userInfo.isNotEmpty) return null;
    return parsePeerEndpoint(uri.host, uri.port);
  }

  // 피어 다이얼 입구: 정규 10진 RFC 1918 IPv4와 포트만 통과시킴. 선행 0(010)은 브라우저가 8진수로 읽어 다른 주소가 되므로
  // 다시 이어 붙여 원문과 같은지 봄. 루프백·APIPA·IPv6는 피어 주소로 안 받음
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

  static void assertReachable(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4 &&
        address.type != InternetAddressType.IPv6) {
      throw SecurityException('blocked non-IP target ${address.address}');
    }
    if (!isLinkLocalOrPrivate(address.address)) {
      throw SecurityException('blocked WAN target ${address.address}');
    }
  }

  // 192.168 > 10 > 172.16/12 > 169.254 순. 루프백은 뺌: 거기 붙으면 다른 기기는 못 닿는데
  // 서버는 떠 있는 걸로 보여서 '네트워크 없음'을 영영 못 띄움
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

    // IPv4 LAN이 없으면 IPv6 ULA로 감 (링크로컬은 스코프 ID 없이 다이얼이 안 돼서 뺌)
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

  // 바인드할 LAN 주소가 없을 때 대신 받은 공인·CGNAT 주소. 이것도 없으면 진짜 네트워크 없음
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

  // 리다이렉트(3xx)·WebSocket 업그레이드로 여는 소켓까지 connectionFactory 한 곳에서 다시 검사함.
  // wrap으로 연결된 소켓에 수신 상한 래퍼 등을 씌울 수 있음
  static HttpClient createPeerHttpClient({Socket Function(Socket)? wrap}) =>
      createPeerHttpClientImpl(wrap: wrap);

  // 사설 주소가 여러 개면 진짜 Wi-Fi·이더넷부터 고름. 대역 순위만 보면 VM·테더링 브리지, VPN(utun),
  // 셀룰러(pdp_ip)가 받은 10.x에 붙어서 QR 주소가 LAN에서 안 닿음. 169.254는 맨 끝, 이름 규칙에 없는 인터페이스는 그 사이에 둠
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
