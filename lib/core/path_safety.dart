import 'dart:convert';

import 'package:path/path.dart' as p;

import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/path_safety_names.dart';

// 상대가 보낸 file_offer의 name으로 파일을 쓰니 경로를 믿으면 안 됨 (../
// 탈출, NUL 바이트, 중첩 traversal, 절대경로, Windows 예약명/금지 문자)
// safeBasename(이름 정제)과 resolveWithin(결과가 선택한 폴더 안인지 증명)
// 두 레이어가 각각 단독으로도 막음. lexical 검사라 TOCTOU 심링크 교체는 못 막음

// 디렉토리 부분, 구분자, .., 제어문자, Windows 금지문자·예약명을 없애고 UTF-8 바이트 길이를 제한함
// 빈 문자열, ".", ".."는 안 돌려줌. NFD 한글은 normalizeHangulNfc로 합침
// (전송/표시용 이름 전용, 실제 파일을 여는 원본 경로엔 안 씀)
String safeBasename(String rawName) {
  // 역슬래시를 슬래시로 접고 마지막 / 뒤만 남김 (Windows/POSIX 구분자 둘 다 처리)
  var name = rawName.replaceAll('\\', '/');
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  name = p.basename(name); // 이중 방어
  name = normalizeHangulNfc(name);

  // 제어·서식 문자 삭제: C0·DEL·C1(Cc), 양방향 제어(U+202E RLO 등)·폭 없는 문자(Cf), 줄·문단 구분자.
  // 'invoice\u202Etxt.exe'가 채팅·탐색기에서 'invoiceexe.txt'처럼 보이는 확장자 위장을 막음
  // .. 토큰 전부 삭제 (replaceAll은 전역이라 ....도 무너짐), Windows 금지 문자는 밑줄로 치환
  name = name
      .replaceAll(RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true), '')
      .replaceAll('..', '')
      .replaceAll(RegExp(r'[<>:"|?*]'), '_')
      .trim();
  // 길이부터 맞춤: 아래 끝 점·공백 정리와 장치 이름 검사가 잘린 결과에 걸려야 함
  // ('NUL' + 공백 300칸 + 'x'를 나중에 자르면 'NUL   '이 남고 Windows가 끝 공백을 지워 장치로 열림)
  name = _fitLength(name);
  // Windows 탐색기가 이름 끝의 점/공백을 조용히 지워서, 안 지우면 우리가 만든 이름과
  // 사용자가 보는 이름이 달라짐
  while (name.isNotEmpty && (name.endsWith('.') || name.endsWith(' '))) {
    name = name.substring(0, name.length - 1);
  }

  if (name.isEmpty || name == '.' || name == '..') {
    return 'received-file';
  }

  // 첫 '.' 앞이 장치 이름이면 확장자가 몇 개든(NUL.tar.gz), 끝 공백이 있든(CON .txt) 장치로 열림.
  // 점으로 시작하는 이름은 숨김 설정 파일(.bashrc 등)이 되지 않게 접두사를 붙임
  if (isWindowsReservedStem(name.split('.').first.trimRight()) ||
      name.startsWith('.')) {
    name = '_$name';
  }
  return name;
}

// 파일시스템 이름 한도(255바이트)보다 한참 낮게 유지. 확장자는 별도 예산으로 지켜
// 올바른 앱으로 열리게 하고, 나머지를 stem이 씀
String _fitLength(String name) {
  final ext = truncateUtf8(p.extension(name), kMaxExtensionBytes);
  final stem = truncateUtf8(
    p.basenameWithoutExtension(name),
    kMaxBasenameBytes - utf8.encode(ext).length,
  );
  return '$stem$ext';
}

// safeBasename 결과가 실제로 directory 안인지 증명하는 두 번째 레이어
// 디렉토리 자체거나 밖이면 SecurityException. normalization 특이점이나 심링크가
// safeBasename을 빠져나갔을 때의 fail-safe
String resolveWithin(String directory, String fileName) {
  final base = p.normalize(p.absolute(directory));
  final target = p.normalize(p.join(base, safeBasename(fileName)));
  if (target == base || !p.isWithin(base, target)) {
    throw SecurityException(
      'blocked path traversal: "$fileName" escapes "$directory"',
    );
  }
  return target;
}
