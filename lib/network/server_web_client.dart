part of 'local_server.dart';

// 브라우저 게스트용 HTML 한 장
extension LocalServerWebClient on LocalServer {
  Future<Response> _serveWebClient() async {
    if (_webClientCache == null) {
      final shell = await rootBundle.loadString('assets/web/index.html');
      final css = await _concatAssets([
        'assets/web/css/theme.css',
        'assets/web/css/layout.css',
      ]);
      // plain 스크립트라 이어 붙이는 순서가 곧 정의 순서 (app.js가 마지막)
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
      // CSP는 실제 인라인 블록의 해시만 허용함
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

  // 소스는 여러 파일이어도 한 문서로 인라인해서 브라우저는 요청 하나로 끝남
  static Future<String> _concatAssets(List<String> paths) async {
    final parts = await Future.wait(paths.map(rootBundle.loadString));
    return parts.join('\n');
  }
}
