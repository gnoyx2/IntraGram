part of 'local_server.dart';

extension LocalServerRoutes on LocalServer {
  // 모든 응답에 no-store와 보안 헤더를 설정함. Host 헤더가 바인드 주소와 다르면 421을 반환함 (DNS 리바인딩으로 외부 출처가 로컬 서버를 호출하는 공격을 차단함)
  Middleware _noStore() => (Handler inner) {
    return (Request request) async {
      final expected = boundHost == null
          ? null
          : '${NetworkGuard.hostForUri(boundHost!)}:$boundPort';
      if (expected == null || request.headers['host'] != expected) {
        return Response(
          421,
          body: 'Misdirected Request',
          headers: _securityHeaders,
        );
      }
      // absolute-form 요청(GET http://외부호스트/...)은 dart:io가 URI 쪽 호스트를 사용하므로 Host와 다르면 거절함
      if (request.requestedUri.authority != expected) {
        return Response(400, body: 'Bad Request', headers: _securityHeaders);
      }
      final response = await inner(request);
      return response.change(
        headers: {
          ..._securityHeaders,
          if (response.headers['content-security-policy']
              case final String policy)
            'content-security-policy': policy,
        },
      );
    };
  };

  // dart:io가 Host로 요청 URI를 못 만드는 요청(쉼표 목록 Host 등)은 shelf_io가 Request를 만들다 던져서
  // 미들웨어를 안 거친 500이 됨: shelf에 넘기기 전에 400으로 끝냄
  bool _parsable(HttpRequest request) {
    try {
      return request.requestedUri.hasScheme;
    } on FormatException {
      final response = request.response..statusCode = HttpStatus.badRequest;
      _securityHeaders.forEach(response.headers.set);
      response.write('Bad Request');
      unawaited(response.close());
      return false;
    }
  }

  Middleware _rejectNonLocal() => (Handler inner) {
    return (Request request) {
      final info = request.context['shelf.io.connection_info'];
      if (info is HttpConnectionInfo &&
          !NetworkGuard.isLinkLocalOrPrivate(info.remoteAddress.address)) {
        return Response.forbidden('local link only');
      }
      return inner(request);
    };
  };

  Future<Response> _route(Request request) async {
    final path = '/${request.url.path}';
    if (path == '/ws') return _upgrade(request);

    switch ((request.method, path)) {
      case ('GET', '/') || ('GET', '/index.html'):
        return _serveWebClient();
      case ('POST', '/api/transfer'):
        return _receiveFile(request);
      case ('GET', '/health'):
        return _health();
      default:
        if (request.method == 'GET' && path.startsWith('/api/download/')) {
          return _downloadFile(
            path.substring('/api/download/'.length),
            request.headers,
          );
        }
        return Response.notFound('Intragram: nothing here.');
    }
  }

  Response _upgrade(Request request) {
    final info = request.context['shelf.io.connection_info'];
    final remoteHost = info is HttpConnectionInfo
        ? info.remoteAddress.address
        : '0.0.0.0';
    final remotePort = info is HttpConnectionInfo ? info.remotePort : null;

    // 브라우저는 동일 출처여도 WS 핸드셰이크에 Origin 헤더를 포함함. 앱 피어(Dart 클라이언트)는 미포함하므로 null이면 허용함
    final origin = request.headers['origin'];
    if (origin != null && !_isOwnOrigin(origin)) {
      return Response.forbidden('origin not allowed');
    }

    return upgradeToCappedWebSocket(
      request,
      // 아직 아무것도 안 보낸 소켓은 hello 크기만큼, 그 뒤는 프레임 상한만큼만 모이게 둠
      limit: (messages) =>
          wireBudget(messages, registry.store.largeMessageMode),
      pingInterval: kSocketPingInterval,
      onConnection: (channel) {
        if (!NetworkGuard.isLinkLocalOrPrivate(remoteHost)) {
          channel.sink.close();
          return;
        }
        unawaited(
          registry
              .acceptInbound(
                channel,
                remoteHost: remoteHost,
                remotePort: remotePort,
                requiredWebToken: () => portalToken,
              )
              .then<void>((_) {}, onError: onInboundError),
        );
      },
    );
  }

  // 브라우저 WebSocket은 이 서버가 제공한 동일 origin만 허용함
  bool _isOwnOrigin(String origin) {
    final host = boundHost;
    final port = boundPort;
    if (host == null || port == null) return false;
    return origin == 'http://${NetworkGuard.hostForUri(host)}:$port';
  }

  // 헤더가 다 있고 형식이 맞아야 registry로 감 (아니면 400이고 슬롯은 안 건드림). 검증과 소비는 registry가 함
  Future<Response> _receiveFile(Request request) async {
    final transferId = request.headers['x-transfer-id'];
    if (transferId == null || transferId.isEmpty) {
      return Response(HttpStatus.badRequest, body: 'missing x-transfer-id');
    }
    final attemptId = request.headers['x-transfer-attempt'];
    final declared = int.tryParse(request.headers['x-file-size'] ?? '');
    if (attemptId == null || attemptId.isEmpty || declared == null) {
      return Response(
        HttpStatus.badRequest,
        body: 'missing x-transfer-attempt or x-file-size',
      );
    }
    final accepted = await registry.receiveTransfer(
      transferId: transferId,
      attemptId: attemptId,
      token: request.headers['x-transfer-token'] ?? '',
      body: request.read(),
      headerDeclaredSize: declared,
    );
    return accepted
        ? Response.ok(
            '{"ok":true}',
            headers: {'content-type': 'application/json'},
          )
        : Response.forbidden(
            '{"ok":false,"reason":"rejected"}',
            headers: {'content-type': 'application/json'},
          );
  }

  // 헤더 누락 시 400을 반환함. 인가·봉인·EOF 기록은 레지스트리가 전담하며 여기서는 결과를 Response로 감싸 반환함 (평문 소스를 직접 읽지 않음)
  Future<Response> _downloadFile(
    String transferId,
    Map<String, String> headers,
  ) async {
    final attemptId = headers['x-transfer-attempt'];
    final declared = int.tryParse(headers['x-file-size'] ?? '');
    if (attemptId == null || attemptId.isEmpty || declared == null) {
      return Response(
        HttpStatus.badRequest,
        body: 'missing x-transfer-attempt or x-file-size',
      );
    }
    final OutgoingDownload? download;
    try {
      download = await registry.openDownload(
        transferId: transferId,
        attemptId: attemptId,
        token: headers['x-transfer-token'] ?? '',
        declaredSize: declared,
      );
    } on SecurityException {
      return Response.forbidden('download not authorized');
    }
    if (download == null) return Response.notFound('unknown transfer');

    // wireBytes는 암호화까지 반영된 값 (안 맞으면 dart:io가 응답을 중간에 끊음)
    return Response.ok(
      download.body,
      headers: {
        'content-type':
            lookupMimeType(download.name) ?? 'application/octet-stream',
        'content-disposition': contentDisposition(download.name),
        if (download.wireBytes > 0) 'content-length': '${download.wireBytes}',
      },
    );
  }

  Response _health() {
    return Response.ok(
      jsonEncode(<String, dynamic>{
        'app': kAppName,
        'v': kProtocolVersion,
        'alias': identity.alias,
        'platform': identity.platform,
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}

// RFC 6266: 레거시 클라이언트용 ASCII 파일명(제어 문자·비ASCII·따옴표·역슬래시는 _ 대체)과 UTF-8 원본 파일명을 제공함
// filename*는 RFC 8187 attr-char 외 문자(작은따옴표·괄호·별표 포함)를 퍼센트 인코딩함
@visibleForTesting
String contentDisposition(String name) {
  final ascii = name.replaceAll(RegExp(r'[^\x20-\x7E]|["\\]'), '_');
  final utf8 = Uri.encodeComponent(name).replaceAllMapped(
    RegExp(r"[!'()*]"),
    (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
  );
  return "attachment; filename=\"$ascii\"; filename*=UTF-8''$utf8";
}

const _portalPolicy =
    "default-src 'none'; img-src 'self' blob: data:; "
    "media-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; "
    "base-uri 'none'; form-action 'none'";
const _securityHeaders = {
  'cache-control': 'no-store',
  'content-security-policy': _portalPolicy,
  'x-frame-options': 'DENY',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  // 게스트 페이지는 카메라·마이크·위치 등을 안 씀. 다른 창·출처와 창 핸들·응답을 나누지 않음
  'permissions-policy':
      'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  'cross-origin-opener-policy': 'same-origin',
  'cross-origin-resource-policy': 'same-origin',
};
