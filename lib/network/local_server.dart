import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:mime/mime.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:intragram/core/app_identity.dart';
import 'package:intragram/core/constants.dart';
import 'package:intragram/core/network_guard.dart';
import 'link_registry.dart';
import 'capped_socket.dart';
import 'ws_upgrade.dart';

part 'server_routes.dart';
part 'server_web_client.dart';

// GET /                  단일 파일 웹 클라이언트 (브라우저 게스트)
// GET /ws                WebSocket 업그레이드 -> 새 인바운드 PeerLink
// POST /api/transfer     인커밍 파일 바이트 스트림 수락
// GET /api/download/<id> 아웃고잉 파일을 브라우저 게스트로 스트리밍
// GET /health            생존 + 신원 프로브
// link-local IPv4에만 바인딩. 기기가 네트워크에 없으면 start가 null을 리턴하고 아무것도 안 들음
class LocalServer {
  LocalServer({
    required this.registry,
    required this.identity,
    required this.onInboundError,
    this.preferredPort = kPreferredPort,
    this.bindAddress,
    this.idleTimeout = kHttpIdleTimeout,
  });

  final LinkRegistry registry;
  final AppIdentity identity;

  final void Function(Object, StackTrace) onInboundError;

  // 테스트는 0을 넘겨 OS가 ephemeral 포트를 배정하게 함 (병렬 실행이 안 겹침)
  final int preferredPort;

  // 넘기면 NetworkGuard.localBindAddress를 안 부르고 이 주소에 바로
  // 바인딩. 테스트 전용 seam (프로덕션은 항상 null = 실제 LAN 인터페이스 탐지)
  final InternetAddress? bindAddress;

  // 요청을 끝까지 안 보내는 연결을 닫기까지의 간격 (실제로는 이 값의 1~2배). 테스트는 짧게 줌
  final Duration idleTimeout;

  HttpServer? _server;
  String? _webClientCache;
  String? _webClientPolicy;

  // 포털이 켜져 있는 동안만 세팅되는 256-bit RAM 전용 입장 토큰(base64url).
  // ServerController.start가 서버가 뜬 직후 채우고 끄면 지움
  // web_hello가 정확히 일치해야 하고, 링크엔 값 복사 대신 조회 콜백을 줘서 포털 OFF 직후 대기 링크도 거부함
  String? portalToken;

  bool get isRunning => _server != null;
  String? get boundHost => _server?.address.address;
  int? get boundPort => _server?.port;

  Future<({String host, int port})?> start() async {
    final running = _server;
    if (running != null) {
      return (host: running.address.address, port: running.port);
    }

    final address = bindAddress ?? await NetworkGuard.localBindAddress();
    if (address == null) return null;

    final handler = const Pipeline()
        .addMiddleware(_noStore())
        .addMiddleware(_rejectNonLocal())
        .addHandler(_route);

    // ephemeral 포트(0)는 한 번만 바인딩되고, 고정 우선 포트는 빈 포트가 나올 때까지 앞으로 훑음
    final ports = preferredPort == 0
        ? const <int>[0]
        : [
            for (var p = preferredPort; p < preferredPort + kPortScanRange; p++)
              p,
          ];

    HttpServer? server;
    for (final port in ports) {
      try {
        server = await HttpServer.bind(address, port);
        break;
      } on SocketException {
        continue; // 포트 사용 중: 다음 후보 시도
      }
    }
    if (server == null) {
      throw StateError('no free port from $preferredPort');
    }
    // 요청을 끝까지 안 보내는 연결을 기본 120초(최대 240초) 대신 빨리 정리함. 웹소켓은 업그레이드 때
    // 서버에서 떨어져 나가서 영향 없음
    server.idleTimeout = idleTimeout;
    // X-Powered-By(서버 지문)를 안 붙임
    shelf_io.serveRequests(
      server.where(_parsable),
      handler,
      poweredByHeader: null,
    );

    _server = server;
    return (host: server.address.address, port: server.port);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
