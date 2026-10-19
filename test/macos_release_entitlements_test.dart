import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Xcode는 ad-hoc/개발 서명 빌드에 get-task-allow(디버거 attach
// 허용)를 기본 주입함. 릴리즈 구성에서 안 끄면 배포하는 앱의 메모리를
// 같은 사용자의 다른 프로세스가 읽을 수 있고 공증(notarization)도
// 거부됨. 네이티브 설정이라 analyze/test가 못 봐서 파일을 읽어 고정
// (33CC10FD…는 Runner 타깃의 Release 구성 id, Flutter macOS 템플릿에서 고정)
void main() {
  test('macOS Release config does not inject debug entitlements', () {
    final pbxproj = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final start = pbxproj.indexOf('33CC10FD2044A3C60003C045 /* Release */ = {');
    expect(start, isNonNegative);
    final block = pbxproj.substring(
      start,
      pbxproj.indexOf('name = Release;', start),
    );

    expect(block, contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;'));
  });

  test('macOS Release entitlements do not allow debugger attach', () {
    final plist = File('macos/Runner/Release.entitlements').readAsStringSync();

    expect(plist, isNot(contains('get-task-allow')));
  });
}
