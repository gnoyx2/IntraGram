import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'apple_localization_test.dart' show resolvedPath;

// Mac App Store 업로드는 앱 분류 키가 없으면 거부되고, 창 위치 복원에 쓰는 UserDefaults는
// required-reason API라 앱의 PrivacyInfo.xcprivacy에 이유를 적어야 함. 네이티브 설정이라 파일을 읽어 고정
void main() {
  final plist = File('macos/Runner/Info.plist').readAsStringSync();
  final pbxproj = File(
    'macos/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  test('Info.plist names an App Store category', () {
    expect(
      RegExp(
        r'<key>LSApplicationCategoryType</key>\s*'
        r'<string>public\.app-category\.[a-z-]+</string>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test('Info.plist answers export compliance like the iOS app', () {
    expect(
      RegExp(
        r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>',
      ).hasMatch(plist),
      isTrue,
    );
  });

  test('the privacy manifest is bundled and gives the UserDefaults reason', () {
    expect(pbxproj, contains('/* PrivacyInfo.xcprivacy in Resources */,'));
    final path = resolvedPath(pbxproj, 'PrivacyInfo.xcprivacy');
    expect(path, 'Runner/PrivacyInfo.xcprivacy');
    final manifest = File('macos/$path').readAsStringSync();
    expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(manifest, contains('<string>CA92.1</string>'));
  });
  test('statvfs space check declares the file-writing DiskSpace reason', () {
    final manifest = File(
      'macos/Runner/PrivacyInfo.xcprivacy',
    ).readAsStringSync();
    expect(manifest, contains('NSPrivacyAccessedAPICategoryDiskSpace'));
    expect(manifest, contains('<string>E174.1</string>'));
    expect(
      File('lib/core/free_space.dart').readAsStringSync(),
      contains("'statvfs'"),
    );
  });
}
