import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 저장소의 iOS 프로젝트는 특정 Apple 팀으로 서명하지 않음 (포크 빌드 시 타인의 팀으로 서명을 시도하는 문제 방지).
// 팀 ID는 git이 무시하는 ios/Flutter/Signing.xcconfig에만 둠
void main() {
  test('the iOS project names no Apple team', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, isNot(contains('DEVELOPMENT_TEAM')));
    for (final config in ['Debug', 'Release']) {
      expect(
        File('ios/Flutter/$config.xcconfig').readAsStringSync(),
        contains('#include? "Signing.xcconfig"'),
        reason: config,
      );
    }
    expect(
      File('ios/.gitignore').readAsStringSync(),
      contains('Flutter/Signing.xcconfig'),
    );
  });
}
