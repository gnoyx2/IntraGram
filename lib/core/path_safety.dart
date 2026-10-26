import 'dart:convert';

import 'package:path/path.dart' as p;

import 'package:intragram/core/network_guard.dart';
import 'package:intragram/core/path_safety_names.dart';

// 상대가 정한 파일 이름이라 못 믿음. safeBasename(이름 정제)과 resolveWithin(폴더 안인지 증명)이 각자 막음.
// lexical 검사라 그 사이 심링크를 바꿔치는 TOCTOU는 못 막음

// 폴더 부분·구분자·..·제어문자·Windows 금지문자/장치 이름을 없애고 바이트 길이를 자름. 빈 값·'.'·'..'는 안 돌려줌.
// 전송·표시용 이름 전용 (실제 파일을 여는 원본 경로엔 쓰면 안 됨)
String safeBasename(String rawName) {
  // 한 번 거른 이름을 또 걸러도 같아야 함: 받는 쪽은 제안 때 한 번, 저장할 때 또 거름.
  // 길이를 자르다 ..가 새로 생기거나 _가 붙어 확장자가 달리 읽히면 다음 번에 바뀔 수 있어 수렴할 때까지 최대 4번 더 돌림
  var name = _sanitizeOnce(rawName);
  for (var i = 0; i < 4; i++) {
    final next = _sanitizeOnce(name);
    if (next == name) break;
    name = next;
  }
  return name;
}

String _sanitizeOnce(String rawName) {
  var name = rawName.replaceAll('\\', '/');
  final slash = name.lastIndexOf('/');
  if (slash >= 0) name = name.substring(slash + 1);
  name = p.basename(name); // 이중 방어
  name = normalizeHangulNfc(name);

  // 서식 문자(U+202E RLO, 폭 없는 문자, 줄 구분자)까지 지움: 'invoice<RLO>txt.exe'가 'invoiceexe.txt'처럼 보이는 위장을 막음.
  // ..는 전부 지우고(replaceAll이라 ....도 무너짐) Windows 금지 문자는 _로 바꿈
  name = name
      .replaceAll(RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true), '')
      .replaceAll('..', '')
      .replaceAll(RegExp(r'[<>:"|?*]'), '_')
      .trim();
  // 길이부터 자름: 끝 점·공백 정리와 장치 이름 검사는 잘린 결과에 걸려야 함 ('NUL' + 공백 300칸 + 'x'가 잘려 'NUL'로 열림)
  name = _fitLength(name);
  // Windows가 이름 끝 점·공백을 조용히 지워서 우리가 쓴 이름과 보이는 이름이 달라짐
  while (name.isNotEmpty && (name.endsWith('.') || name.endsWith(' '))) {
    name = name.substring(0, name.length - 1);
  }

  if (name.isEmpty || name == '.' || name == '..') {
    return 'received-file';
  }

  // 첫 '.' 앞이 장치 이름이면 확장자가 몇 개든(NUL.tar.gz) 장치로 열림. 점으로 시작하면 숨김 설정 파일(.bashrc)이 될 수 있어 _를 붙임
  if (isWindowsReservedStem(name.split('.').first.trimRight()) ||
      name.startsWith('.')) {
    name = '_$name';
  }
  return name;
}

// 255바이트 한도보다 한참 낮게 자름. 확장자는 따로 예산을 둬서 안 잘림 (그래야 맞는 앱으로 열림)
String _fitLength(String name) {
  final ext = truncateUtf8(p.extension(name), kMaxExtensionBytes);
  final stem = truncateUtf8(
    p.basenameWithoutExtension(name),
    kMaxBasenameBytes - utf8.encode(ext).length,
  );
  return '$stem$ext';
}

// safeBasename 결과가 정말 폴더 안인지 다시 증명하는 두 번째 레이어임. 폴더 자체거나 밖이면 SecurityException을 던짐
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
