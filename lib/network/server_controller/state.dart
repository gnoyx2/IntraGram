part of '../server_controller.dart';

// 서버를 못 띄운 이유. 화면 문구와 다음 행동이 다름
enum ServerProblem {
  // Android 17+: 로컬 네트워크 런타임 권한이 꺼짐
  localNetworkDenied,
  // 사설·링크 로컬 IPv4가 하나도 없음 (Wi-Fi 안 붙음)
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
  // failed일 때 원문 (개발자용, 화면엔 번역 문구와 함께 보조로만)
  final String? error;

  // true일 때만 토큰이 있고 웹 게스트가 들어옴
  final bool portalEnabled;

  // 켤 때만 뽑는 256비트 입장 토큰 (RAM). 서버나 포털을 끄면 바로 사라지고 보관소·로그엔 안 감
  final String? portalToken;

  // 브라우저 게스트가 치거나 찍어서 들어오는 주소 (토큰이 없으면 null). 토큰은 #t=로: fragment는 서버로 안 가서
  // 로그·Referer에 안 남고 브라우저가 읽자마자 지움
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
