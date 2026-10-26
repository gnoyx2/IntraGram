part of '../server_controller.dart';

// 서버를 못 띄운 이유. 화면 문구와 다음 행동이 다름
enum ServerProblem {
  // Android 17+: 로컬 네트워크 런타임 권한이 꺼짐
  localNetworkDenied,
  // 사설·링크 로컬 IP(IPv4 또는 IPv6 ULA)가 없음 (Wi-Fi 미연결 등)
  noNetwork,
  // 붙어 있지만 공인·CGNAT 주소만 받음 (캠퍼스·회사 Wi-Fi, 일부 핫스팟): 설계상 안 씀
  notPrivate,
  // 바인드 자체가 실패함 (error에 원문)
  failed,
}

@immutable
class ServerState {
  const ServerState({
    this.running = false,
    this.host,
    this.port,
    this.problem,
    this.address,
    this.error,
    this.portalEnabled = false,
    this.portalToken,
  });

  final bool running;
  final String? host;
  final int? port;
  final ServerProblem? problem;
  // notPrivate일 때 기기가 받은 주소
  final String? address;
  // failed 상태 시 원본 오류 내용임 (디버깅용이며 UI에는 번역된 안내와 함께 보조 표시됨)
  final String? error;

  // true일 때만 토큰이 있고 웹 게스트가 들어옴
  final bool portalEnabled;

  // 켤 때만 뽑는 256비트 입장 토큰 (RAM). 서버나 포털을 끄면 바로 사라지고 보관소·로그엔 안 감
  final String? portalToken;

  // 브라우저 게스트가 접속하는 주소임 (토큰이 없으면 null을 반환함). 토큰은 #t= 해시 프래그먼트로 전달되어
  // HTTP 요청으로 서버에 전송되지 않으며, 서버 로그나 Referer에 노출되지 않고 브라우저가 읽은 후 즉시 제거함
  String? get portalUrl {
    if (!running || host == null || port == null) return null;
    final token = portalToken;
    if (token == null) return null;
    return 'http://${NetworkGuard.hostForUri(host!)}:$port#t=$token';
  }

  ServerState copyWith({
    bool? running,
    String? host,
    int? port,
    bool? portalEnabled,
    String? portalToken,
  }) => ServerState(
    running: running ?? this.running,
    host: host ?? this.host,
    port: port ?? this.port,
    portalEnabled: portalEnabled ?? this.portalEnabled,
    portalToken: portalToken ?? this.portalToken,
  );
}
