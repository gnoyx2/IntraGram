import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

// LocalSend의 open_file / open_folder에서 아이디어만
// 가져옴. open_filex, open_dir, permission_handler는
// 제로 CDN·최소 의존성 원칙에 안 맞아서 플러그인 없이 Process.run으로 다시 구현함
// 데스크톱 전용. 모바일에선 isSupported가 false고 모든 호출이 false를 돌려주는 no-op
final class NativeOpen {
  const NativeOpen._();

  static bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  // 테스트 seam: fake로 바꿔서 셸 메타문자가 든 파일명이 Uri로만 전달되고
  // 명령어로 재해석되지 않는지 검증함
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

  // 열면 OS 앱이 NetworkGuard 밖으로 나가는 형식: 브라우저가 원격 리소스를 불러오는 웹 문서,
  // 인터넷 바로 가기, 원격 데스크톱, 원격 URL 재생 목록, 원격 설치기, 원격 위치를 여는 탐색기 형식
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

  // Windows만: Zone.Identifier ADS에 MOTW(ZoneId=3, 인터넷)를 남겨 SmartScreen/Office 보호 보기가
  // 받은 파일로 취급하게 함. FAT/exFAT/일부 네트워크 드라이브는 ADS가 없어 못 남기고 넘어감
  static Future<void> markFromInternet(String path) async {
    if (!Platform.isWindows) return;
    try {
      await File(
        '$path:Zone.Identifier',
      ).writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n', flush: true);
    } on FileSystemException {
      // 표식만 못 남김. 파일 자체는 이미 저장 완료라 전송을 실패로 돌리지 않음
    }
  }

  static Future<bool> open(String path) async {
    if (!isSupported || !File(path).existsSync()) return false;
    return switch (defaultTargetPlatform) {
      // macOS는 프로세스 안 NSWorkspace(url_launcher)로 엶: 자식 /usr/bin/open엔 사용자가 고른
      // 폴더의 샌드박스 접근 권한이 안 넘어갈 수 있음
      TargetPlatform.macOS => launchUrlOverride(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      ),
      // cmd /c start 대신 url_launcher: 받은 파일 이름은 상대가 정한 값이라 cmd.exe가
      // 인자를 다시 파싱할 때 &/^/괄호가 명령어로 해석될 수 있음
      // launchUrl은 셸 호출 없이 ShellExecute로 경로를 직접 넘김
      TargetPlatform.windows => launchUrlOverride(
        Uri.file(path, windows: true),
        mode: LaunchMode.externalApplication,
      ),
      TargetPlatform.linux => _run('xdg-open', <String>[path]),
      _ => false,
    };
  }

  // macOS NSWorkspace(채널, 프로세스 안), Windows explorer /select,로 파일을 선택 상태로 둠
  // 리눅스는 의존성 없이 하이라이트할 방법이 없어서 부모 폴더만 엶
  static Future<bool> revealInFolder(String path) async {
    if (!isSupported) return false;
    final dir = p.dirname(path);
    if (!File(path).existsSync() && !Directory(dir).existsSync()) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => _revealOnMac(path),
      TargetPlatform.windows => _run('explorer', <String>[
        '/select,${path.replaceAll('/', r'\')}',
      ]),
      TargetPlatform.linux => _run('xdg-open', <String>[dir]),
      _ => false,
    };
  }

  // URL을 OS에 넘기기만 하고 앱이 fetch하진 않음. 에어갭 밖으로 나가는 유일한 지점이라
  // 사용자가 링크를 탭했을 때만 호출됨
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

  static Future<bool> _revealOnMac(String path) async {
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
      // explorer.exe는 성공해도 exit code가 1임
      return executable == 'explorer' || result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }
}
