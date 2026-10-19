import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 네이티브 설정은 analyze/test가 안 봄: Android Auto Backup이
// 앱 데이터 폴더(보관소, 신원 파일)를 클라우드로 올리면 제로 디스크 약속이 깨지므로
// 매니페스트의 백업이 꺼진 채로 유지되는지 고정
void main() {
  test('Android manifest keeps app data out of OS backup', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
  });

  // FGS 타입마다 짝 권한이 있어야 함 (Android 14+는 없으면 startForeground가 SecurityException으로 죽음)
  // 타입·권한·서비스 코드의 상수가 같은 remoteMessaging인지 고정
  test('the background connection service declares one type end to end', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/yonghun0310/intragram/'
      'ConnectionService.kt',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:foregroundServiceType="remoteMessaging"'),
    );
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING'),
    );
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    expect(service, contains('FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING'));
  });

  // QR은 기기 안에서 순수 Dart로 풂: 진단을 Firelog로 올리는 ML Kit가 빌드에 다시 들어오면 Data safety의
  // "수집 없음"이 거짓이 됨. 카메라 플러그인이 끼우는 필수 카메라·옛 저장소 권한도 빼 둠
  test('the QR scanner brings no ML Kit and no storage permission', () {
    final lock = File('pubspec.lock').readAsStringSync();
    expect(lock, isNot(contains('mobile_scanner')));
    expect(lock, isNot(contains('mlkit')));
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      matches(
        RegExp(
          r'android.hardware.camera.any"\s*android:required="false"\s*'
          r'tools:replace="android:required"',
        ),
      ),
    );
    for (final storage in ['WRITE', 'READ']) {
      expect(
        manifest,
        matches(RegExp(storage + r'_EXTERNAL_STORAGE"\s*tools:node="remove"')),
      );
    }
  });

  // 런타임에 요청한 적 없는 위험 권한은 선언도 안 함 (Play 권한 목록에 '주변 기기'가 뜨지 않게)
  test('no nearby Wi-Fi devices permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, isNot(contains('android.permission.NEARBY_WIFI_DEVICES')));
  });

  // 백그라운드 연결 알림: 문구는 리소스(한국어 포함), small icon은 흰 실루엣
  test('the connection notification is localized and uses the status icon', () {
    final service = File(
      'android/app/src/main/kotlin/com/yonghun0310/intragram/'
      'ConnectionService.kt',
    ).readAsStringSync();
    final names = RegExp(r'<string name="(\w+)"');
    Set<String> keys(String path) => names
        .allMatches(File(path).readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    final en = keys('android/app/src/main/res/values/strings.xml');
    expect(en, keys('android/app/src/main/res/values-ko/strings.xml'));
    for (final key in en) {
      expect(service, contains('R.string.$key'));
    }
    expect(service, contains('setSmallIcon(R.drawable.ic_stat_intragram)'));
    expect(
      File('lib/core/notifications.dart').readAsStringSync(),
      contains("'@drawable/ic_stat_intragram'"),
    );
  });
}
