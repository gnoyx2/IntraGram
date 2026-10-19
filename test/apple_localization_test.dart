import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// 권한 팝업 문구(InfoPlist.strings)는 Xcode 타깃 리소스에 붙어야 번들에 들어감. 파일만 있고
// 타깃에 없으면 한국어 기기에서도 영어 팝업이 뜸. 네이티브 설정이라 파일을 읽어 고정
void main() {
  for (final os in ['ios', 'macos']) {
    group(os, () {
      final pbxproj = File(
        '$os/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final plist = File('$os/Runner/Info.plist').readAsStringSync();

      test('InfoPlist.strings is a bundled en/ko resource', () {
        expect(pbxproj, contains('/* InfoPlist.strings in Resources */,'));
        expect(pbxproj, contains('path = en.lproj/InfoPlist.strings;'));
        expect(pbxproj, contains('path = ko.lproj/InfoPlist.strings;'));
        expect(
          RegExp(
            r'<key>CFBundleLocalizations</key>\s*<array>\s*'
            r'<string>en</string>\s*<string>ko</string>',
          ).hasMatch(plist),
          isTrue,
        );
      });

      test('the InfoPlist.strings references point at the real files', () {
        for (final lang in ['en', 'ko']) {
          final path = resolvedPath(pbxproj, '$lang.lproj/InfoPlist.strings');
          expect(File('$os/$path').existsSync(), isTrue, reason: path);
        }
      });

      test('every usage text is translated in both languages', () {
        final keys = RegExp(
          r'<key>(NS\w+UsageDescription)</key>',
        ).allMatches(plist).map((m) => m.group(1)!).toList();
        expect(keys, isNotEmpty);
        for (final lang in ['en', 'ko']) {
          final strings = File(
            '$os/Runner/$lang.lproj/InfoPlist.strings',
          ).readAsStringSync();
          for (final key in keys) {
            expect(strings, contains('"$key" ='), reason: '$lang $key');
          }
        }
      });

      test('the microphone text covers tap-to-record', () {
        final en = File(
          '$os/Runner/en.lproj/InfoPlist.strings',
        ).readAsStringSync();
        final ko = File(
          '$os/Runner/ko.lproj/InfoPlist.strings',
        ).readAsStringSync();
        expect(en, contains('hands-free'));
        expect(ko, contains('핸즈프리'));
        expect(plist, contains('hands-free'));
      });
    });
  }

  test('the macOS menu bar has a Korean localization', () {
    final pbxproj = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final path = resolvedPath(pbxproj, 'ko.lproj/MainMenu.strings');
    expect(path, 'Runner/ko.lproj/MainMenu.strings');
    expect(File('macos/$path').existsSync(), isTrue);
  });
}

// 파일 참조 경로에 부모 그룹들의 path를 차례로 붙여 Xcode가 실제로 찾는 경로를 만듦
// (path = ..인 그룹 밑에 잘못 걸면 빌드에서만 'Build input file cannot be found'로 드러남)
String resolvedPath(String pbxproj, String refPath) {
  const id = '[0-9A-F]{24}';
  final parent = <String, String>{};
  final groupPath = <String, String>{};
  final groups = RegExp(
    '($id) /\\*[^*]*\\*/ = \\{\\s*isa = PBX(?:Variant)?Group;(.*?)\\n\\t\\t\\};',
    dotAll: true,
  );
  for (final group in groups.allMatches(pbxproj)) {
    final body = group.group(2)!;
    final children = RegExp(
      r'children = \((.*?)\);',
      dotAll: true,
    ).firstMatch(body)?.group(1);
    for (final child in RegExp('\\b($id)\\b').allMatches(children ?? '')) {
      parent[child.group(1)!] = group.group(1)!;
    }
    final path = RegExp(r'\n\t\t\tpath = "?([^";]+)"?;').firstMatch(body);
    if (path != null) groupPath[group.group(1)!] = path.group(1)!;
  }
  final ref = RegExp(
    '($id) /\\*[^*]*\\*/ = \\{[^}]*path = ${RegExp.escape(refPath)};',
  ).firstMatch(pbxproj)!.group(1)!;
  final parts = [refPath];
  for (var at = parent[ref]; at != null; at = parent[at]) {
    final path = groupPath[at];
    if (path != null) parts.insert(0, path);
  }
  return p.normalize(p.joinAll(parts));
}
