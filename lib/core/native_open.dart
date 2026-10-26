import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

// 받은 파일 열기·폴더에서 보기 (데스크톱 전용, 모바일은 전부 false). LocalSend open_file·open_folder에서 아이디어만 가져와
// 플러그인 없이 새로 짬
final class NativeOpen {
  const NativeOpen._();

  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  // 테스트에서 바꿔 끼워서 셸 메타문자 든 파일 이름이 Uri로만 넘어가는지 봄
  @visibleForTesting
  static Future<bool> Function(Uri uri, {required LaunchMode mode})
  launchUrlOverride = launchUrl;

  // 열면 바로 코드가 도는 확장자. 받은 파일이면 열기 전에 한 번 묻고 폴더 보기를 권함
  static const Set<String> _executableExts = {
    '.exe',
    '.msi',
    '.com',
    '.scr',
    '.bat',
    '.cmd',
    '.ps1',
    '.vbs',
    '.vbe',
    '.js',
    '.jse',
    '.wsf',
    '.wsh',
    '.hta',
    '.lnk',
    '.reg',
    '.cpl',
    '.msc',
    '.jar',
    '.sh',
    '.bash',
    '.run',
    '.bin',
    '.appimage',
    '.desktop',
    '.deb',
    '.rpm',
    '.command',
    '.terminal',
    '.app',
    '.pkg',
    '.py',
    '.pl',
    // Windows: 옛 단축·도움말·설치 패키지와 탐색기 명령 파일, 열면 바로 마운트되는 디스크 이미지
    '.pif',
    '.chm',
    '.msix',
    '.msixbundle',
    '.appx',
    '.appxbundle',
    '.scf',
    '.iso',
    '.img',
    '.vhd',
    '.vhdx',
  };

  static bool isExecutable(String path) =>
      _executableExts.contains(p.extension(path).toLowerCase());

  // 열면 OS 앱이 NetworkGuard 밖으로 나가는 형식: 원격 리소스를 부르는 웹 문서, 인터넷 바로 가기, 원격 데스크톱,
  // 원격 재생 목록·설치기, 원격 위치를 여는 탐색기 형식
  static const Set<String> _networkExts = {
    '.html',
    '.htm',
    '.xhtml',
    '.svg',
    '.mht',
    '.mhtml',
    '.url',
    '.webloc',
    '.inetloc',
    '.rdp',
    '.m3u',
    '.m3u8',
    '.pls',
    '.xspf',
    '.asx',
    '.jnlp',
    '.appinstaller',
    '.appref-ms',
    '.application',
    '.library-ms',
    '.searchconnector-ms',
  };

  static bool reachesNetwork(String path) =>
      _networkExts.contains(p.extension(path).toLowerCase());

  // Windows만: Zone.Identifier ADS에 MOTW(ZoneId=3)를 남겨 SmartScreen·Office 보호 보기가 받은 파일로 다룸.
  // FAT·exFAT처럼 ADS가 없으면 그냥 넘어감
  static Future<void> markFromInternet(String path) async {
    if (!Platform.isWindows) return;
    try {
      await File(
        '$path:Zone.Identifier',
      ).writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n', flush: true);
    } on FileSystemException {
      // 표식만 못 남긴 거라 전송은 성공으로 둠
    }
  }

  static Future<bool> open(String path) async {
    if (!isSupported || !File(path).existsSync()) return false;
    return switch (defaultTargetPlatform) {
      // macOS는 프로세스 안 NSWorkspace(url_launcher)로 엶: 자식 /usr/bin/open엔 사용자가 고른 폴더의 샌드박스 권한이 안 넘어갈 수 있음
      TargetPlatform.macOS => launchUrlOverride(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      ),
      // cmd /c start 말고 url_launcher(ShellExecute): 상대가 정한 파일 이름의 &·^·괄호를 cmd.exe가 명령으로 읽을 수 있음
      TargetPlatform.windows => launchUrlOverride(
        Uri.file(path, windows: true),
        mode: LaunchMode.externalApplication,
      ),
      TargetPlatform.linux => _run('xdg-open', <String>[path]),
      _ => false,
    };
  }

  // 네이티브 파일 관리자에 경로를 직접 넘겨 선택함 (셸 명령 문자열 없음).
  static Future<bool> revealInFolder(String path) async {
    if (!isSupported) return false;
    final dir = p.dirname(path);
    if (!File(path).existsSync() && !Directory(dir).existsSync()) return false;
    final revealed = await _revealFile(path);
    if (revealed || defaultTargetPlatform != TargetPlatform.linux) {
      return revealed;
    }
    return _run('xdg-open', <String>[dir]);
  }

  // URL을 OS에 넘기기만 함 (앱은 fetch 안 함). 사용자가 링크를 열기로 했을 때만 불림
  static Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    try {
      return await launchUrlOverride(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }

  static const _privacy = MethodChannel('intragram/privacy');

  static Future<bool> _revealFile(String path) async {
    try {
      return await _privacy.invokeMethod<bool>('revealFile', path) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> _run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
