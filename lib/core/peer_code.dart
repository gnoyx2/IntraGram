import 'package:intragram/core/network_guard.dart';

// 앱끼리 잇는 QR 내용. 기기 코드(intragram://<host>:<port>/<peerId>)와 게스트 포털 주소
// (http://<host>:<port>#t=…&p=<peerId>) 둘 다 받음. peerId가 있으면 그 신원을 증명한 상대하고만
// 연결되게 expectedPeerId로 넘김 (화면을 직접 찍은 경로라 중간에서 바꿔치기할 수 없음)
typedef PeerCode = ({String host, int port, String? peerId});

// 휴대폰 카메라 앱이 게스트 포털로 열지 않게 http가 아닌 앱 전용 스킴을 씀
const String kDeviceCodeScheme = 'intragram';

// peerId는 신원 공개키 SHA-256 앞 16바이트의 소문자 hex (app_identity.dart peerIdOfKey)
final RegExp _peerIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _fragmentPeerId = RegExp(r'(?:^|&)p=([^&]*)');

String deviceCode({
  required String host,
  required int port,
  required String peerId,
}) => '$kDeviceCodeScheme://${NetworkGuard.hostForUri(host)}:$port/$peerId';

// 포털 QR에 붙여서 앱이 찍을 때도 신원을 고정함 (브라우저는 t만 읽음)
String portalCodeWithPeer(String portalUrl, String peerId) =>
    '$portalUrl&p=$peerId';

// 사설 IPv4가 아니거나 peerId 형식이 틀리면 null (형식이 틀린 p는 고정 없이 넘기지 않고 코드째 버림)
PeerCode? parsePeerCode(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == kDeviceCodeScheme) return _parseDeviceCode(uri);
  final endpoint = NetworkGuard.parsePeerQr(text);
  if (endpoint == null) return null;
  final peerId = _fragmentPeerId.firstMatch(uri.fragment)?.group(1);
  if (peerId != null && !_peerIdPattern.hasMatch(peerId)) return null;
  return (host: endpoint.host, port: endpoint.port, peerId: peerId);
}

PeerCode? _parseDeviceCode(Uri uri) {
  if (!uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length != 1 || !_peerIdPattern.hasMatch(segments.single)) {
    return null;
  }
  final endpoint = NetworkGuard.parsePeerEndpoint(uri.host, uri.port);
  if (endpoint == null) return null;
  return (host: endpoint.host, port: endpoint.port, peerId: segments.single);
}
