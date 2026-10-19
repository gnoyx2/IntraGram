part of 'local_server.dart';

// 브라우저 게스트용 단일 HTML 웹 클라이언트 (server_routes.dart의 / 라우트가 부름)
extension LocalServerWebClient on LocalServer {
  Future<Response> _serveWebClient() async {
    if (_webClientCache == null) {
      final shell = await rootBundle.loadString('assets/web/index.html');
      final css = await _concatAssets([
        'assets/web/css/theme.css',
        'assets/web/css/layout.css',
      ]);
      // 의존 순서대로 이어붙임 (plain 스크립트라 concat 순서 = 정의 순서): i18n
      // -> socket -> peer_address -> audio_player ->
      // chat_ui -> chat_ui_handlers -> file_transfer ->
      // app.js(엔트리)
      final js = await _concatAssets([
        'assets/web/js/i18n.js',
        'assets/web/js/socket.js',
        'assets/web/js/peer_address.js',
        'assets/web/js/audio_player.js',
        'assets/web/js/chat_ui.js',
        'assets/web/js/chat_ui_handlers.js',
        'assets/web/js/file_transfer.js',
        'assets/web/app.js',
      ]);
      final html = shell
          .replaceFirst('/*__APP_CSS__*/', css)
          .replaceFirst('/*__APP_JS__*/', js);
      // 실제 인라인 블록의 해시만 허용함
      final directives = <String>[];
      for (final tag in ['script', 'style']) {
        final hashes = <String>[];
        for (final match in RegExp(
          '<$tag>([\\s\\S]*?)</$tag>',
        ).allMatches(html)) {
          final hash = await Sha256().hash(utf8.encode(match.group(1)!));
          hashes.add("'sha256-${base64Encode(hash.bytes)}'");
        }
        directives.add("$tag-src ${hashes.join(' ')}");
      }
      // 옛 WebKit(iOS 15대 Safari)은 connect-src 'self'를 ws:에 안 맞춰서 웹소켓이 막힘: 주소를 명시함
      final wsOrigin =
          'ws://${NetworkGuard.hostForUri(boundHost ?? '')}:$boundPort';
      final policy = _portalPolicy.replaceFirst(
        "connect-src 'self'",
        "connect-src 'self' $wsOrigin",
      );
      _webClientPolicy = '$policy; ${directives.join('; ')}';
      _webClientCache = html;
    }
    return Response.ok(
      _webClientCache,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'content-security-policy': _webClientPolicy!,
      },
    );
  }

  // 웹 클라이언트 소스는 여러 파일로 쪼개져 있어도 서버가 한 번에 인라인해서 브라우저가 문서 하나만 받음 (추가 네트워크 요청 없음)
  static Future<String> _concatAssets(List<String> paths) async {
    final parts = await Future.wait(paths.map(rootBundle.loadString));
    return parts.join('\n');
  }
}
